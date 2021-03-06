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

subroutine amoeba_anneal(p,y,pb,yb,ftol,func,iter,temptr)
    USE tdefit_util, ONLY : assert_eq,swap,swap_rv
    integer, intent(inout) :: iter
    real, intent(inout) :: yb
    real, intent(in) :: ftol,temptr
    real, dimension(:), intent(inout) :: y,pb
    real, dimension(:,:), intent(inout) :: p
    interface
        function func(x)
        real, dimension(:), intent(in) :: x
        real :: func
        end function func
    end interface
    integer, parameter :: NMAX=200
    integer :: ihi,ndim
    real :: yhi
    real, dimension(size(p,2)) :: psum
    call amoeba
    CONTAINS

    subroutine amoeba
    integer :: i,ilo,inhi
    real :: rtol,ylo,ynhi,ysave,ytry
    real, dimension(size(y)) :: yt,harvest
    ndim=assert_eq(size(p,2),size(p,1)-1,size(y)-1,size(pb),'amoeba_anneal')
    psum(:)=sum(p(:,:),dim=1)
    do
        call random_number(harvest)
        yt(:)=y(:)-temptr*log(harvest)
        ilo=minloc(yt(:), dim=1)
        ylo=yt(ilo)
        ihi=maxloc(yt(:), dim=1)
        yhi=yt(ihi)
        yt(ihi)=ylo
        inhi=maxloc(yt(:), dim=1)
        ynhi=yt(inhi)
        rtol=2.0*abs(yhi-ylo)/(abs(yhi)+abs(ylo))
        if (rtol < ftol .or. iter < 0) then
            call swap(y(1),y(ilo))
            call swap_rv(p(1,:),p(ilo,:))
            RETURN
        end if
        ytry=amoeba_move(-1.0)
        iter=iter-1
        if (ytry <= ylo) then
            ytry=amoeba_move(2.0)
            iter=iter-1
        else if (ytry >= ynhi) then
            ysave=yhi
            ytry=amoeba_move(0.5)
            iter=iter-1
            if (ytry >= ysave) then
                p(:,:)=0.5*(p(:,:)+spread(p(ilo,:),1,size(p,1)))
                do i=1,ndim+1
                    if (i /= ilo) y(i)=func(p(i,:))
                end do
                iter=iter-ndim
                psum(:)=sum(p(:,:),dim=1)
            end if
        end if
    end do
    end subroutine amoeba

    function amoeba_move(fac)
    real, intent(in) :: fac
    real :: amoeba_move
    real :: fac1,fac2,yflu,ytry,harv
    real, dimension(size(p,2)) :: ptry
    fac1=(1.0-fac)/ndim
    fac2=fac1-fac
    ptry(:)=psum(:)*fac1-p(ihi,:)*fac2
    ytry=func(ptry)
    if (ytry <= yb) then
        pb(:)=ptry(:)
        yb=ytry
    end if
    call random_number(harv)
    yflu=ytry+temptr*log(harv)
    if (yflu < yhi) then
        y(ihi)=ytry
        yhi=yflu
        psum(:)=psum(:)-p(ihi,:)+ptry(:)
        p(ihi,:)=ptry(:)
    end if
    amoeba_move=yflu
    end function amoeba_move
end subroutine amoeba_anneal
