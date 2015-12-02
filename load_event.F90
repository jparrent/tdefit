!This file is part of TDEFit.

!TDEFit is free software: you can redistribute it and/or modify
!it under the terms of the GNU General Public License as published by
!the Free Software Foundation, either version 3 of the License, or
!(at your option) any later version.
!
!TDEFit is distributed in the hope that it will be useful,
!but WITH(out) ANY WARRANTY; without even the implied warranty of
!MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!GNU General Public License for more details.
!
!You should have received a copy of the GNU General Public License
!along with TDEFit.  If not, see <http://www.gnu.org/licenses/>.

subroutine load_event(e, prepare)
#include "tdefit.fpp"
    use tdefit_data
    use constants
    use tdefit_interface, only: bbflux, obs_bb_func, get_band_type
    use tdefit_util, only: sort2


    integer, intent(in)                     :: e
    logical, intent(in)                     :: prepare

    integer                                 :: fn, i, j, bi, ei, band_count, version
    real                                    :: flux, dummy, first_time
    logical                                 :: next_band
    character*1                             :: band_type
    character*2                             :: cur_band
    character*2, dimension(:), allocatable  :: temp_bands
    character*3                             :: time_unit
    real, dimension(:), allocatable         :: temp_times
    character*50 :: var_name, str_value
    character*200 :: buffer
    integer :: int_value, p, pcount, nbuf, stat, begk, endk
    integer :: loc, loc2

    fn = 11

    if (prepare) then
        if (my_pe .eq. 0) print *, "Preparing to load event '" // trim(event_fnames(e)) // "'..."
    else
        if (my_pe .eq. 0) print *, "Loading event '" // trim(event_fnames(e)) // "'..."
    endif
    open(unit = fn, file = trim(event_path) // trim(event_fnames(e)) // ".dat", status='old', action='read')

    ! Read through file twice, first is to simply count number of photometric and BLR points
    stat = 0
    linedo: do
        read(fn, '(A200)', iostat=stat, size=nbuf, advance='no') buffer
        if (is_iostat_eor(stat)) then
            j = 1
            loc = 1
            loc2 = 1
            do while(loc2 .ne. 0)
                loc2 = index(trim(buffer(loc:)), " ")
                if (loc2 .eq. 1) then
                    loc = loc + 1
                    cycle
                endif
                if (loc2 .eq. 0) then
                    begk = loc
                    endk = nbuf
                else
                    begk = loc
                    endk = loc+loc2-2
                    loc = loc + loc2
                endif

                if (j .eq. 1) then
                    read(buffer(begk:endk),*) var_name
                endif

                if (j .gt. 1) then
                    select case (var_name)
                        case ('photometry')
                            if (prepare) then
                                if (j .eq. 2) event_npts(e) = event_npts(e) + 1
                                if (j .gt. 2) cycle linedo
                            endif
                            select case (j)
                                case (2)
                                    read(buffer(begk:endk),*) event_bands(p,e)
                                case (3)
                                    read(buffer(begk:endk),*) event_time_units(p,e)
                                case (4)
                                    read(buffer(begk:endk),*) event_times(p,e)
                                case (5)
                                    read(buffer(begk:endk),*) event_ABs(p,e)
                                case (6)
                                    read(buffer(begk:endk),*) event_errs(p,e)
                                case (7)
                                    read(buffer(begk:endk),*) event_types(p,e)
                                case default
                                    if (my_pe .eq. 0) then
                                        print *, 'Too many columns for photometric point! Aborting.'
                                        call exit(0)
                                    endif
                            end select
                        case ('broad_line')
                            if (prepare) then
                                if (j .eq. 2) event_blrpts(e) = event_blrpts(e) + 1
                                if (j .gt. 2) cycle linedo
                            endif
                            select case (j)
                                case (2)
                                    read(buffer(begk:endk),*) event_blr_time_units(p,e)
                                case (3)
                                    read(buffer(begk:endk),*) event_blr_times(p,e)
                                case (4)
                                    read(buffer(begk:endk),*) event_blr_vels(p,e)
                                case (5)
                                    read(buffer(begk:endk),*) event_blr_bands(p,e)
                                case (6)
                                    read(buffer(begk:endk),*) event_blr_exists(p,e)
                                case default
                                    if (my_pe .eq. 0) then
                                        print *, 'Too many columns for broad line point! Aborting.'
                                        call exit(0)
                                    endif
                            end select
                        case ('redshift')
                            read(buffer(begk:endk),*) event_claimed_z(e)
                        case ('nh')
                            read(buffer(begk:endk),*) event_nh(e)
                        case ('nhcorr')
                            read(buffer(begk:endk),*) event_nhcorr(e)
                        case ('restframe')
                            read(buffer(begk:endk),*) event_restframe(e)
                        case default
                            cycle linedo
                    end select
                endif
            enddo
            if (i .eq. 2) then
                select case (var_name)
                    case ('photometry')
                        if (my_pe .eq. 0) then
                            do p = 1, event_npts(e)
                                write(*,'(A20,E10.3,E10.3,E10.3,E10.3,L10)') var_name, &
                                    event_time_units(p,e), event_times(p,e), &
                                    event_ABs(p,e), event_errs(p,e), event_types(p,e)
                            enddo
                        endif
                end select
            endif
        elseif (is_iostat_end(stat)) then
            exit
        endif
    enddo linedo

    close(fn)

    if (prepare) return

    ! Sanity check some inputs
    if (event_claimed_z(e) .le. 0.d0) then
        print *, 'Invalid redshift specified, aborting.'
        call exit(0)
    endif
    if (event_nh(e) .lt. 0.d0) then
        print *, 'Invalid nh specified, aborting.'
        call exit(0)
    endif
    if (event_npts(e) .eq. 0) then
        print *, 'Must specify at least one photometric point.'
        call exit(0)
    endif

    do i = 1, event_npts(e)
        band_type = get_band_type(event_bands(i,e))
        if (band_type == 'X') then
            event_ABs(i,e) = -event_ABs(i,e)*mag_fac
        endif
    enddo

    first_time = minval(event_times(:,e))
    event_times(:,e) = event_times(:,e) - first_time
    event_blr_times(:,e) = event_blr_times(:,e) - first_time

    do i = 1, event_npts(e)
        if (event_time_units(i,e) == "MJD") then
            event_times(:,e) = event_times(:,e)*day
            event_blr_times(:,e) = event_blr_times(:,e)*day
        elseif (event_time_units(i,e) == 'yrs') then
            event_times(:,e) = event_times(:,e)*yr
            event_blr_times(:,e) = event_blr_times(:,e)*yr
        else
            print *, 'Invalid time unit specified for photometric point in event file, aborting.'
            call exit(0)
        endif
    enddo

    do i = 1, event_blrpts(e)
        if (event_blr_time_units(i,e) == "MJD") then
            event_times(:,e) = event_times(:,e)*day
            event_blr_times(:,e) = event_blr_times(:,e)*day
        elseif (event_blr_time_units(i,e) == 'yrs') then
            event_times(:,e) = event_times(:,e)*yr
            event_blr_times(:,e) = event_blr_times(:,e)*yr
        else
            print *, 'Invalid time unit specified for broad line point in event file, aborting.'
            call exit(0)
        endif
    enddo

    if (event_restframe(e) .eq. 1) then
        event_times(:,e) = event_times(:,e)*(1.d0 + event_claimed_z(e)) ! Redshift stretches events in time, need to remove to get actual time-evolution.
        event_ABs(:,e) = event_ABs(:,e) + mag_fac*dlog(1.d0 + event_claimed_z(e))
    endif
    event_penalties(:,e) = 0
    event_weights(:,e) = 1.d0

    allocate(temp_bands(event_npts(e)))

    temp_bands = event_bands(:event_npts(e),e)
    call sort2(temp_bands, event_times(:event_npts(e),e), 2)
    temp_bands = event_bands(:event_npts(e),e)
    call sort2(temp_bands, event_ABs(:event_npts(e),e), 2)
    temp_bands = event_bands(:event_npts(e),e)
    call sort2(temp_bands, event_errs(:event_npts(e),e), 2)
    temp_bands = event_bands(:event_npts(e),e)
    call sort2(temp_bands, event_types(:event_npts(e),e), 2)
    event_bands(:event_npts(e),e) = temp_bands

    deallocate(temp_bands)

    bi = 1
    ei = 1
    band_count = 0
    cur_band = event_bands(1,e)

    allocate(ll(e)%p)
    cur => ll(e)%p
    cur%band = cur_band

    do i = 2, event_npts(e)+1
        next_band = .false.
        if (i .le. event_npts(e)) then
            if (event_bands(i,e) .ne. cur_band) then
                ei = i - 1
                next_band = .true.
            endif
        else
            ei = i - 1
            next_band = .true.
        endif
        if (next_band) then
            band_count = band_count + 1
            allocate(temp_times(ei - bi + 1))
            temp_times = event_times(bi:ei,e)
            call sort2(temp_times, event_errs(bi:ei,e))
            temp_times = event_times(bi:ei,e)
            call sort2(temp_times, event_ABs(bi:ei,e))
            temp_times = event_times(bi:ei,e)
            call sort2(temp_times, event_types(bi:ei,e))
            temp_times = event_times(bi:ei,e)
            call sort2(temp_times, event_weights(bi:ei,e))
            event_times(bi:ei,e) = temp_times
            deallocate(temp_times)
            do j = bi, ei
                if (event_errs(j,e) .eq. 0.0d0) event_errs(j,e) = upp_lim_err
                if (time_weighted) then
                    if (j .eq. bi) then
                        event_weights(j,e) = (event_times(j+1,e) - event_times(j,e))
                    elseif (j .eq. ei) then
                        event_weights(j,e) = (event_times(j,e) - event_times(j-1,e))
                    else
                        event_weights(j,e) = 0.5d0 * (event_times(j+1,e) - event_times(j-1,e))
                    endif
                endif
            enddo
            if (i .le. event_npts(e)) then
                cur_band = event_bands(i,e)
                allocate(cur%next)
                cur => cur%next
                cur%band = cur_band
                bi = i
                ei = i
            endif
        endif
    enddo

    if (band_count .ne. event_nbest_bands(e) - nextra_bands) then
        write (*, *), 'Error, actual band count does not match header.'
        call exit(0)
    endif

    if (time_weighted) event_weights(:,e) = event_weights(:,e) / sum(event_weights(:,e))

    allocate(temp_times(event_npts(e)))
    temp_times = event_times(:event_npts(e),e)
    call sort2(temp_times, event_bands(:event_npts(e),e), 2)
    temp_times = event_times(:event_npts(e),e)
    call sort2(temp_times, event_ABs(:event_npts(e),e))
    temp_times = event_times(:event_npts(e),e)
    call sort2(temp_times, event_errs(:event_npts(e),e))
    temp_times = event_times(:event_npts(e),e)
    call sort2(temp_times, event_types(:event_npts(e),e))
    temp_times = event_times(:event_npts(e),e)
    call sort2(temp_times, event_weights(:event_npts(e),e))
    event_times(:event_npts(e),e) = temp_times
    deallocate(temp_times)

    cur => ll(e)%p
    do while (associated(cur))
        if (remove_extinction_corr .and. event_nhcorr(e) .eq. 1) then
            ! The light curves are already corrected for extinction, this "uncorrects" the magnitudes by presuming the flux in the band is in the Rayleigh Jeans limit.
            flux = bbflux(obs_bb_func, cur%band, 1.d6, 0.d0, event_nh(e), 0.d0)
            flux = bbflux(obs_bb_func, cur%band, 1.d6, 0.d0, 0.d0, 0.d0)/flux
            do i = 1, event_npts(e)
                if (event_bands(i,e) .ne. cur%band) cycle
                event_ABs(i,e) = event_ABs(i,e) + mag_fac*dlog10(flux)
            enddo
        endif
        cur => cur%next
    enddo

    ! Loop through band list
    cur => ll(e)%p
    i = 0
    do while (associated(cur))
        i = i + 1
        event_best_bands(i,e) = cur%band
        cur => cur%next
    enddo

    do i = 1, nextra_bands
        event_best_bands(event_nbest_bands(e) - nextra_bands + i,e) = extra_bands(i)
    enddo

    ! The error bars don't include intrinsic variability, this updates the error bars to more appropriately reflect the uncertainty.
    !where (event_types .eq. 0)
    !    event_errs = event_errs + mag_fac*dlog10(1.d0 + variability)
    !endwhere
    event_errs(:event_npts(e),e) = event_errs(:,e)**2
end subroutine