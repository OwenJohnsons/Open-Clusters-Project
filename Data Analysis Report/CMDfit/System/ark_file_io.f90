module ark_file_io

  ! This module is the Fortran 90 I/O for the ARK.  It should emulate all the
  ! old calls, except that the facility to write integer*2 images has gone,
  ! and reading such images may not work on certain machines.

  use get_header
  use put_header
  implicit none

  ! If set false the next FITS file to be written will not change the
  ! axis value keywords.
  logical, save :: find_axes=.true.

  ! The number of bytes for a real written to a FITS file.
  integer, parameter :: k4=4

  ! The length of file name strings to be used.
  integer, parameter :: filnam_len=128

  ! The next input and output files, and last input file
  character(len=filnam_len), private, save :: file_in = ' ', file_out, lstfil=' '
  character(len=3), private, save :: filex = '   '
  ! The default file type to be written is ARK.
  integer, private, save :: itypef = 1
  ! Interactive mode is to be used by default.
  logical, private, save :: inter_in=.true., inter_out=.true.
  ! The error array to be written out.
  real, private, save, allocatable, dimension(:) :: yerr_out
  ! The flag array to be written out.
  character, dimension(:,:), allocatable, private, save :: pix_flg_out
  integer, dimension(2), private, save :: naxis_pix_flg
  character(len=filnam_len), private, save :: nxt_pix_file
  ! The last extension read and next extension to read.
  integer, private, save :: lext_in=0, next_in=0, next_out=0
  logical, private, save :: ext_write=.false.
        

  common /bug/ debug
  logical, private :: debug
      
  interface inpark

    module procedure inpark_1d
    module procedure inpark_2d

  end interface 

  interface makark           

    module procedure makark_1d
    module procedure makark_2d
    module procedure makark_3d

  end interface 

  contains

    ! These routines ensure that extension 0 has the header item in it
    ! to make it clear there are subsequent extensions.
    ! You should only need to call this when creating FITS files from 
    ! scratch, otherwise the headers of the files you read in should
    ! be correct for the ones you write out.
    subroutine write_ext()
      ext_write=.true.
    end subroutine write_ext

    subroutine set_find_axes()
      find_axes=.false.
    end subroutine set_find_axes
      
    subroutine no_write_ext()
      ext_write=.false.
      next_out=0
    end subroutine no_write_ext
      
    subroutine nxtark_in(ufile, iext)
      ! Specifies what the next file to be read is called, and tells inpark
      ! not to prompt for the file name
      character(len=*) ::  ufile
      integer, optional :: iext
      inter_in=.false.
      file_in=ufile
      if (present(iext)) then
        next_in=iext
      else
        next_in=0
      end if
    end subroutine nxtark_in

    subroutine nxtark_out(ufile, iext)
      ! Specifies what the next file to be read is called, and tells inpark
      ! not to prompt for the file name
      character(len=*) ::  ufile
      integer, optional :: iext
      inter_out=.false.
      file_out=ufile
      if (present(iext)) then
        next_out=iext
      else
        next_out=0
      end if
    end subroutine nxtark_out
           
    subroutine typark(itype)
      ! Specifies that the next spectrum is to be written as either a
      ! binary or an ASCII file.
      integer :: itype
      itypef=itype
    end subroutine typark
           
    subroutine lstark_in(ufile, iext)
      ! Returns the name of the last file read in.
      character(len=*) ufile
      integer, optional :: iext
      ufile=lstfil
      if (present(iext)) iext=lext_in
    end subroutine lstark_in
           
    subroutine lstark_out(ufile, iext)
      ! Returns the name of the last file written out.
      character(len=*) ufile
      integer, optional :: iext
      ufile=file_out
      if (present(iext)) then
        print*, 'Using a second argument to lstark_out still needs coding.'
        stop
      end if
    end subroutine lstark_out
           
    subroutine extark(ufilex)
      ! Specifies the default file extension.
      character(len=*) :: ufilex
      if (len(ufilex) .gt. 3) then
        print*, 'Warning from ARK S/R EXTARK.  The supplied'
        print*, 'file extension was more than 3 characters.'
      end if
      filex=ufilex
    end subroutine extark

    subroutine quick_for_fudge(iext)
      integer :: iext
      lext_in=iext
    end subroutine quick_for_fudge
           

    integer function inpark_1d(naxis, data, axdata)
                                                                       
      ! Outputs.
      ! The lengths of each axis.
      integer :: naxis
      ! The data.
      real, dimension(:), allocatable :: data
      ! The axis scales.
      real, dimension(:), allocatable :: axdata
                      
      ! Locals
      logical :: there                     
      character(len=8) :: arktyp

100   if (inter_in) then
        call inpprm('INPARK Version 2.0.', filex, lstfil)
        if (lstfil.eq.'end' .or. lstfil.eq.'END') then 
          inpark_1d = -1
          goto 900                 
        end if
      else
        lstfil=file_in
      end if

      ! Inquire to see if the file is there, and at the same time find
      ! out some other useful facts.
      call arkinq(lstfil, filex, there, arktyp)
      if (.not. there) then
        if (inter_in) then
          print*, 'File not found, please try again.'
          goto 100
        else                            
          inpark_1d=-2
          goto 900
        end if       
      end if
      print*, 'Reading file '//trim(lstfil)
      call clear_header()
              
      ! Now go to the appropriate read routine.
      if (arktyp .eq. 'ARK_FITS') then
        if (inter_in) then
          print*, 'ERROR.  This file is an image, not an X-Y file.'
          goto 100
        else
          inpark_1d=-4
          goto 900
        end if
      else if (ArkTyp .eq. 'ARK') Then
        ! ARK file
        call arkark(lstfil, naxis, data, axdata)
        inpark_1d = 1
        itypef=1
      else
        ! IUE File
        call arkiue(lstfil, naxis, data, axdata)
        inpark_1d = 2
        itypef=2
      end if
                                               
900   inter_in=.true.

    end function inpark_1d


      subroutine arkark(lstfil, naxis, data, axdata)

        character(len=*), intent(in) :: lstfil
        integer, intent(out) :: naxis
        real, dimension(:), allocatable, intent(out) :: data, axdata

        real, external :: ripoly

        integer :: iunit, i, iorder
        double precision, dimension(0:9) :: coefs

        call arkopn(iunit, lstfil, ' ', 'old', 'readonly', &
        'unformatted', 'sequential', 0)
        read(iunit) naxis, (dross(i), i = 1, 36)
        if (allocated(data)) deallocate(data)
        allocate(data(naxis))
        if (allocated(axdata)) deallocate(axdata)
        allocate(axdata(naxis))
        read(iunit) (data(i), i = 1, naxis)
        read(iunit) coefs
        close(iunit)
        do i = 0, 9
          if (coefs(i) .ne. 0.0) iorder = i
        end do      
        do i = 1, naxis
          axdata(i) = RIPOLY(i, coefs, iorder)
        end do

      end subroutine arkark

      subroutine arkiue(lstfil, naxis, data, axdata)

        character(len=*), intent(in) :: lstfil
        integer, intent(out) :: naxis
        real, dimension(:), allocatable, intent(out) :: data, axdata

        character(len=80) :: input           
        real :: junk1, junk2
        integer :: i, iunit

        call arkopn(iunit, lstfil, ' ', 'old', 'readonly', &
        'formatted', ' ', 0)
        ! Read the header.
        read(iunit,'(a80)') dross(1)
        read(iunit,'(a80)') dross(2)
        read(iunit,'(a80)') dross(3)
        dross(4)='END'
        naxis=0
        do   
220       Read(iunit, '(A80)', End = 230 ) Input
          read(input, *, end = 220, err = 220 ) junk1, junk2
          naxis = naxis + 1
        end do
230     if (allocated(data)) deallocate(data)
        allocate(data(naxis))
        if (allocated(axdata)) deallocate(axdata)
        allocate(axdata(naxis))
        rewind(iunit)
        read(iunit, '(/,/)')
        do i=1, naxis
240       Read(iunit, '(A80)') Input   
          Read(input, *, end = 240, err = 240 ) axdata(i), data(i)
        End Do              
        close(iunit)

      end subroutine arkiue

        integer function inpyer(yerr, npts)

        real, dimension(:), intent(out), allocatable :: yerr
        ! If the error array will need allocating, set npts.
        integer, optional, intent(in) :: npts

        integer :: iunit, iostat, i, naxis
        character(len=filnam_len) :: wrk_filnam
        character(len=filnam_len) :: wrkstr
        character(len=filnam_len), external :: addon
        real :: junk1, junk2

        character(len=8) :: arktyp
        logical :: there

        inpyer=-2
!       Does an error file exist?
        i=index(lstfil,'.',.true.)
        there=.false.
        if (i > 0) then
          wrk_filnam=lstfil(1:i+1)//lstfil(i+3:i+3)//'e'
          call arkinq(wrk_filnam, ' ', there, arktyp)
        end if
        if (present(npts)) then
          if (allocated(yerr)) deallocate(yerr)
          allocate(yerr(npts))
        end if
        if (there) then
          print*, 'And error file '//trim(wrk_filnam)
          if (ArkTyp .eq. 'ARK') Then  ! ARK file
            call arkopn(iunit, wrk_filnam, ' ', 'old', 'readonly', &
            'unformatted', 'sequential', 0)
!           Skip out reading header.
            read(iunit) naxis
            read(iunit) (yerr(i), i = 1, naxis)
!           Skip reading X-axis.
            close(iunit)
            inpyer=1
          else ! IUE File     
            call arkopn(iunit, wrk_filnam, ' ', 'old', 'readonly', &
            'formatted', ' ', 0)
!           Skip the header.
            read(iunit,'(a80)') wrkstr
            read(iunit,'(a80)') wrkstr
            read(iunit,'(a80)') wrkstr
            readloop: do i=1, size(yerr)
              tryloop: do
                read(iunit, '(a80)', iostat=iostat) wrkstr
                if (iostat < 0) exit readloop
                Read(wrkstr, *, iostat=iostat) junk1, yerr(i)
                if (iostat == 0) exit tryloop
              end do tryloop
            end do readloop
            close(iunit)
            inpyer=2
          end if
        else if (itypef == 2) then
          inpyer = 2
          call arkopn(iunit, lstfil, ' ', 'old', 'readonly', &
          'formatted', ' ', 0)
          ! Read the header.
          read(iunit,'(a80)') wrkstr
          read(iunit,'(a80)') wrkstr
          read(iunit,'(a80)') wrkstr
          read: do i=1, size(yerr)
            try: do
              read(iunit, '(a80)', iostat=iostat) wrkstr
              if (iostat == 0) then
                read(wrkstr, *, iostat=iostat) junk1, junk2, yerr(i)
                if (iostat == 0) exit try
              else if (iostat < 0) then
                ! End of file.
                if (i < size(yerr)) then
                  ! Hmm.  Reached end-of-file before reading all the
                  ! required data.  Better tell someone.
                  inpyer=-5
                end if
                exit read
              else
                ! Some other error.
                inpyer = -5
                exit read
              end if
            end do try
          end do read
          close(iunit)
        end if

        end function inpyer



        integer function makyer(yerr)

        real, dimension(:) :: yerr        

        allocate(yerr_out(size(yerr)))
        yerr_out=yerr

        makyer=1

        end function makyer

    integer function inpark_2d(naxis, data, axdata)
                                                                       
      ! Outputs.
      ! The lengths of each axis.
      integer, dimension(2) :: naxis
      ! The data.
      real, dimension(:,:), allocatable :: data
      ! The axis scales.
      real, dimension(:,:), allocatable :: axdata
                      
      ! Locals           
      logical :: there
      character(len=8) :: arktyp
      integer :: ifail
      real, external :: ripoly
      real, allocatable, dimension(:) :: data_1d, axdata_1D

100   if (inter_in) then
        call inpprm('INPARK Version 2.0.', filex, lstfil)
        if (lstfil.eq.'end' .or. lstfil.eq.'END') then 
          inpark_2d = -1
          goto 900
        end if
        if (debug) print*, '@ Called in interactive mode, returning file name ', lstfil
        if (debug) print*, '@ And the next extension ', next_in
      else
        lstfil=file_in
        if (debug) print*, '@ Called in batch mode for file ', trim(lstfil)
      end if

      ! Inquire to see if the file is there, and at the same time find
      ! out some other useful facts.
      call arkinq(lstfil, filex, there, arktyp)
      if (.not. there) then
        if (inter_in) then
          print*, 'File not found, please try again.'
          goto 100
        else                            
          inpark_2d=-2
          goto 900
        end if       
      end if
      if (next_in > 0) then
        print*, 'Reading file '//trim(lstfil)//' extension ', next_in
      else
        print*, 'Reading file '//trim(lstfil)
      end if
      call clear_header()
              
      ! Now go to the appropriate read routine.
      if (arktyp .eq. 'ARK_FITS') then
        call arkfit(data, naxis, axdata, ifail, inter_in, lstfil)
        if (ifail==-5 .and. next_in>0) then
          ! Probably failed trying to read beyond the last extension.
          ! See if we can do the next file.
          next_in=0
          if (inter_in) then
            ! Try for another file
            goto 100
          else
            ! In batch mode, let's return. 
            inpark_2d=-5
          end if
        else if (ifail > -1) then
          itypef=3
          inpark_2d=3
          lext_in =next_in
          next_out=next_in
          !next_in=next_in+1
        else                    
          inpark_2d=ifail
        end if
      else 
        ! An ARK or IUE file.
        naxis(2)=1
        if (ArkTyp .eq. 'ARK') Then
          ! ARK file
          call arkark(lstfil, naxis(1), data_1D, axdata_1D)
          inpark_2d = 1
          itypef=1
        else 
          ! IUE File     
          call arkiue(lstfil, naxis(1), data_1D, axdata_1D)
          inpark_2d = 2
          itypef=2                
        end if
        ! Now sort out putting a 1D array into a 2D one.  
        if (allocated(data)) deallocate(data)
        allocate(data(size(data_1D),1))
        data(:,1)=data_1D
        deallocate(data_1D)
        if (allocated(axdata)) deallocate(axdata)
        allocate(axdata(size(axdata_1D),1))
        axdata(:,1)=axdata_1D
        deallocate(axdata_1D)
      end if
                    
900   inter_in=.true.

    end function inpark_2d                               

        subroutine arkfit(data, naxis, axdata, ifail, inter, lstfil)
                                                 
!       ifail is returned as 3 for success.
                                           
!       Passed variables.
        integer, dimension(2) :: naxis
        real, dimension(:,:), allocatable :: data, axdata
        integer ifail
        logical inter
        character(len=*) :: lstfil
                     
!       Locals.
        integer*2 inblk(1440)
        integer*2 :: i2work
        integer(kind=k4), dimension(2880/4) :: relblk
        character, dimension(2880) :: chrblk
        double precision bscale, bzero, crval1, crval2, cdelt1, cdelt2
        double precision :: crpix1, crpix2
        logical scale
        integer i, iblk, icount, max1, max2, j, nbit, iunit
        logical :: bswap=.true.
        integer(kind=k4) :: r4work
        integer :: numaxis
        character(len=10) :: ark_fits_bswap
        logical :: gsm_test

        character :: simple
                                 
!       Functions called.
        logical, external :: arkgsm
                                                                
        iunit=0

        if (debug) print*, '@ arkfit is calling ext_skip to skip to extension ', next_in, &
        ' for unit ', iunit
        i=ext_skip(lstfil, inter, iunit, next_in)

        call fithed(lstfil, inter, iunit, ifail)
        if (ifail == -1) then
          if (debug) print*, '@ Probably read beyond the last extension.'
          ifail=-5
          goto 900
        end if

        ifail=3

        i=get_header_i('NAXIS', numaxis)
        if (next_in==0 .and. numaxis==0) then
          naxis=0
          nbit=0
          if (allocated(data)) deallocate(data)
          allocate(data(0,0))
          if (allocated(axdata)) deallocate(axdata)
          allocate(axdata(0,2))
          goto 890
        end if

        inquire(iunit, nextrec=iblk)

        i=get_header_i('BITPIX', nbit)
        if (abs(nbit)/=32 .and. nbit/=16 .and. nbit/=8) then
          if (inter) then
            print*, '* Warning BITPIX =', nbit
          else
            ifail=-30
            goto 900
          end if
        end if
        if (get_header_i('NAXIS1', naxis(1)) < 1) then
          if (inter) then
            print*, '* Failed to read naxis(1) for FITS header.'
            print*, '> Please give naxis(1) for this file.'
            read(*,*) naxis(1)
          else
            ifail=-3
            goto 900
          end if            
        end if
        if (numaxis == 1) then
          naxis(2)=1
        else
          if (get_header_i('NAXIS2', naxis(2)) < 1) then
            if (inter) then
              print*, '* Failed to read naxis(2) for FITS header.'
              print*, '> Please give naxis(2) for this file.'
              read(*,*) naxis(2)
            else
              ifail=-3
              goto 900
            end if
          end if
        end if
        if (debug) print*, '@ Array is ', naxis(1), 'x', naxis(2)
        scale=.false.
        if (get_header_d('BSCALE', bscale) .gt. 0) then
          if (debug) print*, '@ bscale is ', bscale
          scale=.true.
        else
          bscale=1.0d0
        end if
        if (get_header_d('BZERO', bzero) .gt. 0) then
          if (debug) print*, '@ bzero is ', bzero
          scale=.true.
        else
          bzero=0.0d0
        end if
              
        if (allocated(data)) deallocate(data)
        allocate(data(naxis(1),naxis(2)))
        if (allocated(axdata)) deallocate(axdata)
        allocate(axdata(maxval(naxis),2))

!       Check that reasonable naxis(1) and naxis(2) values have been found.
        if (naxis(1).gt.size(data,1) .or. naxis(2).gt.size(data,2)) then
          if (inter) then
            print*,'* Possible error in data array dimensions.'
            print*,'* Program data array size is ', size(data,1), &
            'x', size(data,2)
            print*,'* Data file header gives size as ', &
            naxis(1),'x',naxis(2)
          else
            ifail=-99
            goto 900
          end if
        end if
        if (size(axdata,1) .lt. max(naxis(1), naxis(2))) then
          if (inter) then
            print*, '* Possible error in axdata array dimensions.'
            print*, '* Program size is ', size(axdata,1)
            print*, '* Data file header gives longest axis as ', &
            max(naxis(1), naxis(2))
          else
            ifail=-97
            goto 900
          end if
        end if

        ! Do we need to byte swap?
        bswap=.true.
        if (arkgsm('ARK_FITS_BSWAP', ark_fits_bswap)) then
          if (trim(ark_fits_bswap) == 'FALSE') bswap=.false.
        end if

        ! Very old-style ark files would have the simple keyword (unlike, say, extensions
        ! of multi-image fits files).
        if (get_header_c('SIMPLE', simple) > 0) then
          ! The simple keyword is not there for extensions.
          if (simple == 'A') then 
            ! Old style ark files.  Who knows if we need to byte swap or
            ! not (the byte order was the natural one for the system on
            ! which they were written)?  Lets assume they were written
            ! swapped.
            bswap=.false.
          end if
        end if
        if (debug) print*, '@ BSWAP is ', bswap

        ! Obtain the axis information.
        if (get_header_d('CRVAL1', crval1) .lt. 1) crval1=1.0d+00
        if (get_header_d('CDELT1', cdelt1) .lt. 1) then
          if (get_header_d('CD1_1', cdelt1) .lt. 1) cdelt1=1.0d+00
        end if
        if (get_header_d('CRPIX1', crpix1) .lt. 1) crpix1=1.0d+00
        if (get_header_d('CRVAL2', crval2) .lt. 1) then
          if (get_header_d('CD2_2', cdelt2) .lt. 1) cdelt2=1.0d+00
        end if
        if (get_header_d('CDELT2', cdelt2) .lt. 1) cdelt2=1.0d+00
        if (get_header_d('CRPIX2', crpix2) .lt. 1) crpix2=1.0d+00
        do 610 i=1, naxis(1)
          axdata(i,1)=real(crval1 + (dble(i)-crpix1)*cdelt1)
610     continue
        do 620 i=1, naxis(2)
          axdata(i,2)=real(crval2 + (dble(i)-crpix2)*cdelt2)
620     continue

!       Read the data.
        max1=naxis(1)
        max2=naxis(2)
        if (abs(nbit) == 32) then
          icount=2880/4
          do j=1, max2
            do i=1, max1
              if (icount .eq. 2880/4) then
                if (debug) print*, '@ About to read block ', iblk
                read(unit=iunit, rec=iblk) relblk
                iblk=iblk+1
                icount=0
              end if
              icount=icount+1
              if (bswap) then
                r4work=relblk(icount)
                call mvbits(r4work,  0, 8, relblk(icount), 24)
                call mvbits(r4work,  8, 8, relblk(icount), 16)
                call mvbits(r4work, 16, 8, relblk(icount),  8)
                call mvbits(r4work, 24, 8, relblk(icount),  0)
              end if
              if (nbit > 0) then
                data(i,j)=real(relblk(icount))
              else
                data(i,j)=transfer(relblk(icount),0.0)
              end if
            end do
          end do
        else if (nbit == 16) then
          icount=2880/2
          do j=1, max2
            do i=1, max1
              if (icount .eq. 2880/2) then
                if (debug) print*, '@ About to read block ', iblk
                read(unit=iunit, rec=iblk) inblk
                iblk=iblk+1
                icount=0
              end if
              icount=icount+1
              if (bswap) then
                i2work=inblk(icount)
                call mvbits(i2work, 0, 8, inblk(icount), 8)
                call mvbits(i2work, 8, 8, inblk(icount), 0)
              end if
              data(i,j)=inblk(icount)
            end do
          end do
        else if (nbit == 8) then
          icount=2880
          do j=1, max2
            do i=1, max1
              if (icount .eq. 2880) then
                if (debug) print*, '@ About to read block ', iblk
                read(unit=iunit, rec=iblk) chrblk
                iblk=iblk+1
                icount=0
              end if
              icount=icount+1       
              data(i,j)=ichar(chrblk(icount))
            end do
          end do
        end if                

        if (scale) then
          if (debug) print*, '@ Applying scale factors...'
          do 470 j=1, naxis(2)
            do 460 i=1, naxis(1)
              data(i,j)=sngl(dble(data(i,j))*bscale + bzero)
460         continue
470       continue
        end if
              
        if (debug) then
          print*, '@ Test data point (1,1) = ', data(1,1)
        end if

890     if (get_header_s('ARK-FLAG', nxt_pix_file) < 1) nxt_pix_file=' '
900     close(iunit)
        end subroutine arkfit
                                      

        subroutine fithed(lstfil, inter, iunit, ifail)

        character(len=*) :: lstfil
        ! On input the first block of header to read, on output the 
        ! first block of data after the header. 
        logical, intent(in) :: inter
        integer, intent(inout) :: iunit
        integer, intent(out) :: ifail

        logical :: opened

        character(len=80) :: form

!       Locals.
        integer i, ndrec, ndrs36
        character expkey*8
        integer :: iblk, iostat
                   
        ifail=0

!       Blank out the header.
        dross=' '

        if (debug) print*, 'In fithed unit =', iunit
        if (iunit /= 0) inquire(iunit, opened=opened)
        if (.not.opened .or. iunit==0) then
          call arkopn(iunit, lstfil, filex, 'OLD', 'APPEND', &
          'UNFORMATTED', 'DIRECT', 2880)
        end if
        inquire(iunit, nextrec=iblk)
        if (debug) print*, 'Fithed thinks header begins at block ', iblk

        do 220 ndrec=iblk, iblk+100
          ndrs36=(ndrec-iblk+1)*36
          if (debug) print*, '@ About to read header block ', ndrec
          inquire(unit=iunit, form=form)
          if (ndrs36 .gt. size(dross)) then
            if (inter) then               
              print*, '* Warning, some of the header is lost'
              print*, '* because there are more than ', size(dross), ' lines.'
            end if
            read (unit=iunit, rec=ndrec, iostat=iostat) (dross(i), i=size(dross)-35,  size(dross))
          else
            read (unit=iunit, rec=ndrec, iostat=iostat) (dross(i), i=ndrs36-35,  ndrs36)
          end if
          if (iostat /= 0) then
            ! O.K., we've read a block that's not there.  Read the previous 
            ! block to that so that inquire works fine.
            read(unit=iunit, rec=ndrec-1)
            ifail=-1
            goto 900
          end if 
          if (debug) print*, '@ Read header block ', ndrec
!         See if we have an end statement yet.
          i=matkey('END', expkey)
          if (i .gt. 0) then
            if (debug) print*,'@ "END" statement found at line ', i
            goto 400
          end if
220     continue
!       If you get to here then no end statement has been found.
        if (inter) then
          print*,'* Failed to find FITS file header "END" statement.'
          ifail=-8
          goto 900
        end if
400     if (debug) print*,'@ There are ', ndrs36, ' lines of header.'
        if (debug) then
          do i=1, ndrs36
            !print*, dross(i)(1:60)
          end do
        end if
        iblk=ndrs36/36 + 1

900     end subroutine fithed


        subroutine inpprm(caller, filext, nxtfil)

        ! Returns the name of the next file to be read, prompting
        ! if needs be.

        ! Inputs.
        ! The name of the calling routine.
        character(len=*), intent(in) :: caller
        ! The current requested file name (may include wild cards).
        !character(len=*), intent(inout) :: file
        ! Is this in batch or interactive mode?
        !logical, intent(in) :: inter
        ! The current default file extension.
        character(len=*), intent(inout) :: filext
        ! The name of the next file to be read.
        character(len=*), intent(out) :: nxtfil

        ! Locals
        character(len=80) :: input
        character(len=filnam_len), save :: fildef=' '
        character(len=3), save :: extdef=' '
        character(len=78) :: outstr
        character (len=8) :: arktyp
        integer, save :: lunit=5
        logical, save :: lastf=.true.
        logical :: there
        integer :: iostat
        character(len=2), save :: imext_def=' '
        integer :: ifirst_blank, iend_string

80      if (lastf) then
          ! The last file read was the last one which matched the
          ! wild card.
          get_name: do
            ! Running in interactive mode, so prompt for new file,
            ! first checking to see if there is a default file extension.
            ! Don't print a prompt if reading from a file.
            if (lunit == 5) then
              if (filext(1:1).ne.' ' .and. filext(1:1).ne.char(0)) then
                outstr='Give input file '// &
                '(".'//filext//'" is assumed, "?" gives help)>'
                call writen(outstr(1:52))
              else
                outstr='Give input file ("?" gives help)>'
                call writen(outstr(1:33))
              end if
            end if
            read (lunit, '(a)', end=800) input
            ! Now, this string may have just a file name, or a file name
            ! and an extension number.
            ! Find index of first blank.
            ifirst_blank = index(input,' ')
            ! Find length of input.
            iend_string = len_trim(input)
            ! Filename is input up to first blank.
            fildef=input(1:ifirst_blank)
            imext_def=input(ifirst_blank+1:iend_string)
            ! If imext_def is composed entirely of blanks, len_trim returns 0.
            if (len_trim(imext_def) == 0) then
              imext_def = '--'
            else
              ! Otherwise, move leading blanks to trailing blanks, so
              ! imext_def starts with the input that came after any blanks.
              imext_def=adjustl(imext_def)
            end if
            if (fildef(1:1) .eq. '#') then
              call arkcom(fildef(2:50))
            else if (fildef(1:1) .eq. '?') then
              print*, 'You are currently in '//caller
              print*, 'You can either;'
              print*, '    1) Give an input file name (wild cards are'
              print*, '       allowed) and optionally an extension number.'
              print*, '    2) Type "end" or EoF to exit without reading'
              print*, '       a file.'
              print*, '    3) Access the operating system by typing "#"'
              print*, '       followed by a command.'
              print*, '    4) Redisplay this help by typing "?".'
              print*, '    5) Give a new default file name extension by'
              print*, '       typing "EXT".'
              print*, '    6) Give a file with a list of file names in'
              print*, '       by typing "@filename".'
              if (filext(1:1).ne.' ' .and. filext(1:1).ne.char(0)) then
                print*, 'The default file name extansion is ', filext, '.'
              end if
            else if (fildef.eq.'ext' .or. fildef.eq.'EXT') then
110           call writen('Give new file name extension (<4 letters)>')
              read (*,'(a)',err=110, end=110) filext
            else if (fildef(1:1) .eq. '@') then
              call arkinq(fildef(2:100), 'lis', there, arktyp)
              if (there) then
                call arkopn(lunit, fildef(2:100), 'lis', 'OLD', &
                'READONLY', 'FORMATTED', ' ', 0)
                 ! Now stop wildf finding a file.
                 fildef=' '
              else
                print*, 'Cannot file file of file names ', trim(fildef)
              end if
            else
              exit get_name
            end if       
          end do get_name
          ! Finally we can update the defination of the file extension.
          extdef=filext
        end if

        ! Now (at last) get the name of the file, allowing for wild cards.
        if (debug) print*, '@ Inpprm is calling wildf_ext.'
        iostat=wildf_ext(fildef, extdef, imext_def, lastf, nxtfil, next_in)
        if (debug) print*, '@ Which returned ', trim(nxtfil), next_in
        if (iostat == -1) then
          print*, 'The requested file is a FITS file with extensions.'
          print*, 'Please give the file name AND extension number.'
          goto 80
        end if
        goto 900

800     if (lunit .eq. 5) then
          nxtfil='END'
        else
          lunit=5
          goto 80
        end if
                                  
900     end subroutine inpprm


        integer function makark_1d(naxis, data, axdata)
                                                                       
!       Inputs.
!       The actual lengths of each axis for the data.
        integer :: naxis 
!       The data.    
        real, dimension (:) :: data
!       The axis scales. 
        real, dimension (:) :: axdata
                      
!       Locals.
        integer :: iunit, i, j

!       For writing ARK files.
        real, dimension(naxis) :: axis
        real :: rms
        double precision, dimension(10) :: coefs
        integer iorder
!       For the header
        character(len=8) :: key
        character(len=20) :: nodnam = 'XXXXXXXXXXXXXXXXXXXX'
        logical :: arknod
                                             
!       Functions called.
        logical, external :: arkgsm
        character(len=filnam_len), external :: addon

        if (inter_out) call pmtout(.true.)
        if (file_out.eq.'end' .or. file_out.eq.'END') then
          print*, 'WARNING:: NO output file written.'
          makark_1d=-1
          return
        end if
                                     
!       Add the ARK node to the header.
        if (nodnam .eq. 'XXXXXXXXXXXXXXXXXXXX') &
        arknod = arkgsm( 'ARK_NODE', nodnam)
        if (.not. arknod) then
          call rem_header('ARK_NODE')
        else          
          call put_header_s('ARK-NODE', nodnam, &
          'COMPUTER FILE CREATED ON',1)
        end if

!       Does the user want us to write errors?
        if (allocated(yerr_out)) itypef = 2
              
!       Clear out any misleading header items.
        call rem_header('NAXIS2')
        if (itypef == 2) then
          call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
          'FORMATTED', 'SEQUENTIAL', 0)
!         Now write the header
          j = 0
          do i=1, size(dross)
            key = dross(i)(1:8)
            If ( Key .ne. 'SIMPLE  ' .and. Key .ne. 'REALTYPE' &
              .and. Key .ne. 'NAXIS   ' .and. Key .ne. 'NAXIS1  ' &
              .and. Key .ne. 'ARK-NODE' .and. Key .ne. 'END' ) Then
              j=j+1
              write(iunit, '(a65)') dross(i)(1:65)
            end if
            if (j .ge. 3) exit
          end do
!         And the data.
          if (allocated(yerr_out)) then
            do j=1, naxis
              write(iunit,*) axdata(j), data(j), yerr_out(j)
            end do
            deallocate(yerr_out)
          else
            do j=1, naxis
              write(iunit,*) axdata(j), data(j)
            end do
          end if
          close(iunit)
        else
          call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
          'UNFORMATTED', 'SEQUENTIAL', 0)
!         Let the user add comments.
          if (inter_out) call makcom(36)                  
!         Construct the header.
          call put_header_c('SIMPLE', 'T', 'ARK FILE', 1)
          call put_header_s('REALTYPE', 'IEEE', 'IEEE REALS', 1)
          call put_header_i('NAXIS', 1, 'ONE DIMENSIONAL', 1)
          call put_header_i('NAXIS1', naxis, 'NO OF DATA POINTS', 1)
!         Calculate the X-axis polynomial.
          rms = 0.01*(axdata(naxis)-axdata(1))/naxis
          do i=1, naxis
            axis(i)=axdata(i)
          end do
          iorder=9
          call ltcheb(axis, naxis, coefs, iorder, RMS)
          write(iunit) naxis, (dross(i), i=1, 36)
          write(iunit) (data(i), i=1, naxis)
          write(iunit) coefs
          close(iunit)
          itypef=1
        end if

        makark_1d=itypef
                
!       Reset inter.
        inter_out=.true.
        print*, 'Written file ', trim(file_out)

999     end function makark_1d


        integer function makark_2d(naxis, data, axdata)
                                                                       
!       Inputs.
!       The actual lengths of each axis for the data.
        integer, dimension(2) :: naxis
!       The data.
        real, dimension (:,:) :: data
!       The axis scales. 
        real, dimension (:,:) :: axdata
                      
!       Locals.
        integer :: iunit, i, j

!       For writing ARK files.
        real, dimension(naxis(1)) :: axis
        real :: rms
        double precision, dimension(10) :: coefs
        integer iorder
        character(len=8) :: key
        character(len=20) :: nodnam = 'XXXXXXXXXXXXXXXXXXXX'
        logical :: arknod
        logical :: oneD
        character(len=filnam_len) :: flgnam

!       Functions called.
        logical, external :: arkgsm
        character(len=filnam_len), external :: addon

        if (naxis(2)>1 .or. naxis(1)*naxis(2)==0) then
          oneD=.false.
        else
          oneD=.true.
        end if
        ! if (.not. ext_write) next_out=0
        if (inter_out .and. next_out==0) call pmtout(oneD)
        if (file_out.eq.'end' .or. file_out.eq.'END') then
          print*, 'WARNING:: NO output file written.'
          makark_2d=-1
          return
        end if

!       Add the ARK node to the header.
        if (nodnam .eq. 'XXXXXXXXXXXXXXXXXXXX') &
        arknod = arkgsm( 'ARK_NODE', nodnam)
        if (.not. arknod) then
          call rem_header('ARK_NODE')
        else          
          call put_header_s('ARK-NODE', nodnam, &
          'COMPUTER FILE CREATED ON',1)
        end if

        if (oneD) then
!         Clear out any misleading header items.
          call rem_header('NAXIS2')
          if (itypef .eq. 2) then
            call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
            'FORMATTED', 'SEQUENTIAL', 0)
!           Now write the header
            j = 0
            do i=1, size(dross)
              key = dross(i)(1:8)
              If ( Key .ne. 'SIMPLE  ' .and. Key .ne. 'REALTYPE' &
                .and. Key .ne. 'NAXIS   ' .and. Key .ne. 'NAXIS1  ' &
                .and. Key .ne. 'ARK-NODE' .and. Key .ne. 'END' ) Then
                j=j+1
                write(iunit, '(a65)') dross(i)(1:65)
              end if
              if (j .ge. 3) exit
            end do
!           And the data.
            do j=1, naxis(1)
              write(iunit,*) axdata(j,1), data(j,1)
            end do
          else
            call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
            'UNFORMATTED', 'SEQUENTIAL', 0)
!           Let the user add comments.
            if (inter_out) call makcom(36)                  
!           Construct the header.
            call put_header_c('SIMPLE', 'T', 'ARK FILE', 1)
            call put_header_s('REALTYPE', 'IEEE', 'IEEE REALS', 1)
            call put_header_i('NAXIS', 1, 'ONE DIMENSIONAL', 1)
            call put_header_i('NAXIS1', naxis(1), 'NO OF DATA POINTS', 1)
!           Calculate the X-axis polynomial.
            rms = 0.01*(axdata(naxis(1),1)-axdata(1,1))/naxis(1)
            do i=1, naxis(1)
              axis(i)=axdata(i,1)
            end do
            iorder=9
            call ltcheb(axis, naxis(1), coefs, iorder, RMS)
            write(iunit) naxis(1), (dross(i), i=1, 36)
            write(iunit) (data(i,1), i=1, naxis(1))
            write(iunit) coefs
            close(iunit)
            itypef=1
          end if
        else
          if (next_out > 0) then         
            call arkopn(iunit, file_out, filex, 'OLD', 'OVERWRITE', &
            'UNFORMATTED', 'DIRECT', 2880)
          else
            call arkopn(iunit, file_out, filex, 'REPLACE', 'OVERWRITE', &
            'UNFORMATTED', 'DIRECT', 2880)
          end if
          if (inter_out .and. next_out==0) call makcom(size(dross))
          if (allocated(pix_flg_out)) then
            flgnam=file_out
            i=index(flgnam, '.', .true.)
            if (i /= 0) flgnam(i:len(flgnam))=' '
            flgnam=trim(flgnam)//'.flg'
            call put_header_s('ARK-FLAG', flgnam, 'ASSOCIATED FLAG FILE', 1)
          end if
          call putfit(iunit, data, axdata, naxis)
          itypef=3
          if (allocated(pix_flg_out)) call makflg2(flgnam)                
        end if
        makark_2d=itypef

!       Reset inter.
        inter_out=.true.
        if (next_out > 0) then
          print*, 'Written file '//trim(file_out)//' extension ', next_out
        else
          print*, 'Written file '//trim(file_out)
        end if

999     end function makark_2d

                                               

        integer function makark_3d(naxis, data, axdata)
                                                                       
!       Inputs.
!       The actual lengths of each axis for the data.
        integer, dimension(3) :: naxis
!       The data.
        real, dimension (:,:,:) :: data
!       The axis scales. 
        real, dimension (:,:) :: axdata
                      
!       Locals.
        integer :: iunit, i, j
        logical oneD       

!       For writing ARK files.
        real, dimension(max(naxis(1),naxis(2),naxis(3))) :: axis
        real :: rms
        double precision, dimension(10) :: coefs
        integer iorder
        character(len=8) :: key
        character(len=20) :: nodnam = 'XXXXXXXXXXXXXXXXXXXX'
        logical :: arknod

!       Functions called.
        logical, external :: arkgsm
        character(len=filnam_len), external :: addon

        if (debug) then
          print*, '@ Entering makark_3d, with;'
          print*, '@    naxis being ', naxis(1), naxis(2), naxis(3)
          print*, '@    the shape of data being ', &
          size(data,1), size(data,2), size(data,3)
          print*, '@    and axdata being ', &
          size(axdata,1), size(axdata,2)
        end if
       

        if (naxis(2) .gt. 1) then
          oneD=.false.
        else
          oneD=.true.
        end if
        if (inter_out) call pmtout(oneD)
        if (file_out.eq.'end' .or. file_out.eq.'END') then
          print*, 'WARNING:: NO output file written.'
          makark_3d=-1
          return
        end if

!       Add the ARK node to the header.
        if (nodnam .eq. 'XXXXXXXXXXXXXXXXXXXX') &
        arknod = arkgsm( 'ARK_NODE', nodnam)
        if (.not. arknod) then
          call rem_header('ARK_NODE')
        else          
          call put_header_s('ARK-NODE', nodnam, &
          'COMPUTER FILE CREATED ON',1)
        end if
                           
        if (oneD) then
!         Clear out any misleading header items.
          call rem_header('NAXIS2')
          call rem_header('NAXIS3')
          if (itypef .eq. 2) then
            call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
            'FORMATTED', 'SEQUENTIAL', 0)
!           Now write the header
            j = 0
            do i=1, size(dross)
              key = dross(i)(1:8)
              If ( Key .ne. 'SIMPLE  ' .and. Key .ne. 'REALTYPE' &
                .and. Key .ne. 'NAXIS   ' .and. Key .ne. 'NAXIS1  ' &
                .and. Key .ne. 'ARK-NODE' .and. Key .ne. 'END' ) Then
                j=j+1
                write(iunit, '(a65)') dross(i)(1:65)
              end if
              if (j .ge. 3) exit
            end do
!           And the data.
            do j=1, naxis(1)
              write(iunit,*) axdata(j,1), data(j,1,1)
            end do
          else
            call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
            'UNFORMATTED', 'SEQUENTIAL', 0)
!           Let the user add comments.
            if (inter_out) call makcom(36)                  
!           Construct the header.
            call put_header_c('SIMPLE', 'T', 'ARK FILE', 1)
            call put_header_s('REALTYPE', 'IEEE', 'IEEE REALS', 1)
            call put_header_i('NAXIS', 1, 'ONE DIMENSIONAL', 1)
            call put_header_i('NAXIS1', naxis(1), 'NO OF DATA POINTS', 1)
!           Calculate the X-axis polynomial.
            rms = 0.01*(axdata(naxis(1),1)-axdata(1,1))/naxis(1)
            do i=1, naxis(1)
              axis(i)=axdata(i,1)
            end do
            iorder=9
            call ltcheb(axis, naxis(1), coefs, iorder, RMS)
            write(iunit) naxis(1), (dross(i), i=1, 36)
            write(iunit) (data(i,1,1), i=1, naxis(1))
            write(iunit) coefs
            close(iunit)
            itypef=1
          end if
        else         
          call arkopn(iunit, file_out, filex, 'NEW', 'OVERWRITE', &
          'UNFORMATTED', 'DIRECT', 2880)
          if (inter_out) call makcom(size(dross))
          call putfit_3d(iunit, data, axdata, naxis)
          itypef=3
        end if
        makark_3d=itypef
                
!       Reset inter.
        inter_out=.true.
        print*, 'Written file ', trim(file_out)

999     end function makark_3d


        subroutine putfit(iunit, data, axdata, naxis)
                                                             
        integer, dimension(2), intent(in) :: naxis(2)
        integer :: iunit
        real, intent(in), dimension(:,:) :: data, axdata
                                
!       Locals
        integer(kind=k4), dimension(2880/4) :: intblk
        real(kind=k4), dimension(2880/4) :: relblk
        character*50 wrkstr
        character(len=7) :: ark_fits_bswap
        logical, external :: arkgsm
        integer i, j, iblk, jblk, icount
!       For the axis information.
        double precision coefs(10)
        real :: rms, target_rms
        integer iorder
                                      
!       The header information.
        character(len=80), allocatable, dimension(:) :: safe_dross

        real, dimension(max(naxis(1),naxis(2))) :: axis

!       Get the operating system name.
        if (.not. arkgsm('ARK_FITS_BSWAP', ark_fits_bswap)) ark_fits_bswap=' '

!       First few manditory key words.
        call put_header_c('SIMPLE', 'T', 'AN ARK_FITS FILE',1)
        call put_header_i('BITPIX', -32, '32 BIT REAL NUMBERS',1)
        call rem_header('REALTYPE')
        if (sum(naxis) > 0) then
          if (product(naxis) > 0) then
            call put_header_i('NAXIS', 2, 'NUMBER OF AXES',1)
          else
            call put_header_i('NAXIS', 1, 'NUMBER OF AXES',1)
          end if
        else
          call put_header_i('NAXIS', 0, 'NUMBER OF AXES',1)
        end if
                                                         
!       Write in the data size.
        if (naxis(1) > 0) then
          call put_header_i('NAXIS1', naxis(1), &
          'NUMBER OF PIXELS ALONG AXIS 1', 1)
        else
          if (naxis(2) > 0) then
            call put_header_i('NAXIS1', naxis(2), &
            'NUMBER OF PIXELS ALONG AXIS 1', 1)
          else
            call rem_header('NAXIS1')
          end if
        end if
        if (product(naxis) > 0) then
          call put_header_i('NAXIS2', naxis(2), &
          'NUMBER OF PIXELS ALONG AXIS 2', 1)
        else
          call rem_header('NAXIS2')
        end if

!       Check BSCALE and BZERO havn't crept in.
        call rem_header('BSCALE')
        call rem_header('BZERO')
        if (ext_write) then
          if (sum(naxis) == 0) then
            call put_header_c('EXTEND', 'T', 'File contains extensions.',1)
          else
            dross(1)="XTENSION= 'IMAGE   '           /"
          end if
        end if

        if (next_out > 0) dross(1)="XTENSION= 'IMAGE   '           /"
                                           
!       Now add an axis array.
        if (find_axes) then
          if (naxis(1) > 0) then
            iorder=1
            target_rms=abs(0.01*(axdata(naxis(1),1)-axdata(1,1))/naxis(1))
            rms=target_rms
            call ltcheb(axdata(1:naxis(1),1), naxis(1), coefs, iorder, RMS )
            if (rms > target_rms) &
            print*, 'Warning, fit to AXIS1 scale has RMS of ', RMS
            if (abs(coefs(2)) < tiny(coefs(2))) coefs(2)=1.0
            call put_header_d('CRVAL1', coefs(1)+coefs(2), '  ', 1)
            call put_header_d('CDELT1', coefs(2), '  ', 1)
            call put_header_r('CRPIX1', 1.0, ' ', 1)
          end if
          if (naxis(2) > 0) then
            iorder=1
            target_rms = abs(0.01*(axdata(naxis(2),2)-axdata(1,2))/naxis(2))
            rms=target_rms
            call ltcheb(axdata(1:naxis(2),2), naxis(2), coefs, iorder, RMS )
            if (rms > target_rms) &
            print*, 'Warning, fit to AXIS2 scale has RMS of ', RMS
            if (abs(coefs(2)) < tiny(coefs(2))) coefs(2)=1.0
            if (naxis(1) > 0) then
              call put_header_d('CRVAL2', coefs(1)+coefs(2), '  ', 1)
              call put_header_d('CDELT2', coefs(2), '  ', 1)
              call put_header_r('CRPIX2', 1.0, ' ', 1)
            else
              call put_header_d('CRVAL1', coefs(1)+coefs(2), '  ', 1)
              call put_header_d('CDELT1', coefs(2), '  ', 1)
              call put_header_r('CRPIX1', 1.0, ' ', 1)
            end if
          end if
        end if
        find_axes=.true.
          
        ! Now, if we are writing an extension, lets get to the end
        ! of the file.
        if (next_out > 0) then
          allocate(safe_dross(size(dross)))
          safe_dross=dross
          i=ext_skip(file_out, inter_out, iunit, next_out)
          inquire(iunit, nextrec=iblk)
          dross=safe_dross
          deallocate(safe_dross)
        else
          iblk=1
        end if

        jblk=lndrss()
        if (mod(jblk,36) .eq. 0) then
          jblk=jblk/36
        else
          jblk=jblk/36 + 1    
        end if
        do i=iblk, iblk+jblk-1
          write (iunit,rec=i) (dross(j),j=(i-iblk+1)*36-35,(i-iblk+1)*36)
          if (debug) print*,'@ Written header block ', i
        end do

        if (naxis(1)>0 .or. naxis(2)>0) then
          icount=0
          inquire(iunit, nextrec=iblk)
          if (trim(ark_fits_bswap) == 'FALSE') then
            ! This is a system which does not need a byte swap.
            do j=1, max(naxis(2),2)
              do i=1, max(naxis(1),1)
                if (icount .eq. 2880/4) then
                  write (iunit, rec=iblk) relblk
                  if (debug) print*, '@ Written data block ', iblk
                  icount=0
                  iblk=iblk+1
                end if
                icount=icount+1
                relblk(icount)=data(i,j)
              end do
            end do
            write (iunit, rec=iblk) relblk
          else
            ! Have to byte swap (how tiresome).
            do j=1, max(naxis(2),1)
              do i=1, max(naxis(1),1)
                if (icount .eq. 2880/4) then
                  write (iunit, rec=iblk) intblk
                  if (debug) print*, '@ Written data block ', iblk
                  icount=0
                  iblk=iblk+1
                end if
                icount=icount+1
                call mvbits(transfer(data(i,j), 0_k4),  0, 8, intblk(icount), 24)
                call mvbits(transfer(data(i,j), 0_k4),  8, 8, intblk(icount), 16)
                call mvbits(transfer(data(i,j), 0_k4), 16, 8, intblk(icount),  8)
                call mvbits(transfer(data(i,j), 0_k4), 24, 8, intblk(icount),  0)
              end do
            end do
            write (iunit, rec=iblk) intblk
          end if
          if (debug) print*, '@ written last data block ', iblk
          if (debug) print*, '@ Test data point (1,1) = ', data(1,1)
        end if
              

!       Tidy up and exit.
900     close(iunit)
        end subroutine putfit


        subroutine putfit_3d(iunit, data, axdata, naxis)
                                                             
        integer naxis(3), iunit
        real, dimension(:,:) :: axdata
        real, dimension(:,:,:) :: data
                                
!       Locals     
        integer(kind=k4), dimension(2880/4) :: intblk
        real(kind=k4), dimension(2880/4) :: relblk
        character*50 wrkstr
        character(len=7) :: ark_fits_bswap
        logical, external ::  arkgsm
        integer i, j, k, iblk, icount
!       For the axis information.
        double precision coefs(10)
        real rms
        integer iorder
                                      
        real, dimension(max(naxis(1),naxis(2),naxis(3))) :: axis

        if (debug) print*, '@ Entering putfit_3d.'
                            
!       Get the operating system name.
        if (.not. arkgsm('ARK_FITS_BSWAP', ark_fits_bswap)) ark_fits_bswap=' '
                                                  
!       First few manditory key words.
        call put_header_c('SIMPLE', 'T', 'AN ARK_FITS FILE',1)
        call put_header_i('BITPIX', -32, 'BIT REAL NUMBERS', 1)
        call rem_header('REALTYPE')
        call put_header_i('NAXIS', 3, 'NUMBER OF AXES',1)
                                                         
!       Check BSCALE and BZERO havn't crept in.
        call rem_header('BSCALE')
        call rem_header('BZERO')

!       Write in the data size.
        call put_header_i('NAXIS1', naxis(1), &
        'NUMBER OF PIXELS ALONG AXIS 1', 1)
        call put_header_i('NAXIS2', naxis(2), &
        'NUMBER OF PIXELS ALONG AXIS 2', 1)
        call put_header_i('NAXIS3', naxis(3), &
        'NUMBER OF PIXELS ALONG AXIS 3', 1)
                                           
        if (debug) print*, '@ Creating axis data.'

!       Now add an axis array.
        if (find_axes) then
          do j=1, 3
            do i=1, naxis(j)
              axis(i)=axdata(i,j)
            end do
            if (debug) print*, '@ Calling ltcheb.'
            iorder=1
            call ltcheb(axis, naxis(j), coefs, iorder, RMS )
            if (rms > 0.01*(axdata(naxis(j),1)-axdata(1,j))/naxis(j)) &
            print*, 'Warning, fit to AXIS', j, 'scale has RMS of ', RMS
            if (debug) print*, '@ Done with ltcheb.'
            if (j .eq. 1) then
              call put_header_d('CRVAL1', coefs(1)+coefs(2), '  ', 1)
              call put_header_d('CDELT1', coefs(2), '  ', 1)
              call put_header_r('CRPIX1', 1.0, ' ', 1)
            else if (j .eq. 2) then
              call put_header_d('CRVAL2', coefs(1)+coefs(2), '  ', 1)
              call put_header_d('CDELT2', coefs(2), '  ', 1)
              call put_header_r('CRPIX2', 1.0, ' ', 1)
            else if (j .eq. 3) then
              call put_header_d('CRVAL3', coefs(1)+coefs(2), '  ', 1)
              call put_header_d('CDELT3', coefs(2), '  ', 1)
              call put_header_r('CRPIX3', 1.0, ' ', 1)
            end if
          end do
        end if
        find_axes=.true.

        if (debug) print*, '@ About to write header.'

        iblk=lndrss()
        if (mod(iblk,36) .eq. 0) then
          iblk=iblk/36
        else
          iblk=iblk/36 + 1    
        end if
        do 110 i=1, iblk
          write (iunit,rec=i) (dross(j),j=i*36-35,i*36)
          if (debug) print*,'@ Written header block ', i
110     continue

        icount=0
        iblk=iblk+1
        if (trim(ark_fits_bswap) == 'FALSE') then
          ! This is a system which does not need a byte swap.
          do k=1, max(naxis(3),3)
            do j=1, max(naxis(2),2)
              do i=1, max(naxis(1),1)
                if (icount .eq. 2880/4) then
                  write (iunit, rec=iblk) relblk
                  if (debug) print*, '@ Written data block ', iblk
                  icount=0
                  iblk=iblk+1
                end if
                icount=icount+1
                relblk(icount)=data(i,j,k)
              end do
            end do
          end do
          if (debug) print*, '@ written last data block ', iblk
          write (iunit, rec=iblk) relblk
        else
          ! Have to byte swap (how tiresome).
          do k=1, max(naxis(3),3)
            do j=1, max(naxis(2),1)
              do i=1, max(naxis(1),1)
                if (icount .eq. 2880/4) then
                  write (iunit, rec=iblk) intblk
                  if (debug) print*, '@ Written data block ', iblk
                  icount=0
                  iblk=iblk+1
                end if
                icount=icount+1
                call mvbits(transfer(data(i,j,k), 0_k4),  0, 8, intblk(icount), 24)
                call mvbits(transfer(data(i,j,k), 0_k4),  8, 8, intblk(icount), 16)
                call mvbits(transfer(data(i,j,k), 0_k4), 16, 8, intblk(icount),  8)
                call mvbits(transfer(data(i,j,k), 0_k4), 24, 8, intblk(icount),  0)
              end do
            end do
          end do
          write (iunit, rec=iblk) intblk
          if (debug) print*, '@ written last data block ', iblk
        end if
        if (debug) print*, '@ Test data point (1,1) = ', data(1,1,1)
                                                             
!       Tidy up and exit.
900     close(iunit)
                    
        end subroutine putfit_3d



        subroutine makcom(lines)
                                
!       Allows the user to add comments.
                                        
        integer lines
                     
        character*79 outstr
        integer linmax, i
                      
        linmax=lndrss()
        if (linmax .ge. lines) goto 900
        linmax=lines-linmax
                           
        outstr='Enter comments below, up to     lines'// &
        ' (<68 letters/line) ...<CR> when finished.'
        write(outstr(29:31), '(i3)') linmax
140     write(*,*) outstr
        do 310 i=1, linmax
          outstr=' '
          Read( *, '(A79)', End = 900 ) outstr
          if (outstr .eq. ' ' ) goto 900
          call put_header_s('COMMENT', outstr, ' ', 0)
310     continue
                
900     end subroutine makcom

  subroutine pmtout(oneD)

! Passed variable.
  logical :: oneD

! Locals.
  character(len=78) :: outstr

! First read in the file name.
100  if (filex(1:1).ne.' ' .and. filex(1:1).ne.char(0)) then
    outstr='Give output file '// &
    '(".'//filex//'" is assumed, "?" gives help)>'
    call writen(outstr(1:53))
  else
    outstr='Give output file '//'("?" gives help)>'
    call writen(outstr(1:34))
  end if
  read (*,'(a)',end=980) file_out
  if (file_out(1:1) .eq. '#') then
    call arkcom(file_out(2:50))
    goto 100
  else if (file_out(1:1) .eq. '?') then
    print*, 'You are currently in MARARK Version 2.0.'
    print*, 'You can either;'
    print*, '    1) Give an output file name.'
    print*, '    2) Type "end" or EoF to exit without writing'
    print*, '       a file.'
    print*, '    3) Access the operating system by typing "#"'
    print*, '       followed by a command.'
    print*, '    4) Redisplay this help by typing "?".'
    print*, '    5) Give a new default file name extension by'
    print*, '       typing "EXT".'
    if (oneD) then
      print*, '    6) Force the next file written to be an'
      print*, '       ASCII file by typing "ASCII".'
      print*, '    7) Force the next file written to be an'
      print*, '       ARK file by typing "ARK".'
      if (itypef .eq. 2) then
        print*, 'The next file will be written in ASCII.'
      else
        print*, 'The next file will be written in ARK format.'
      end if
    else
      print*,'The next file will be written in ARK_FITS format.'
    end if
    if (filex(1:1).ne.' ' .and. filex(1:1).ne.char(0)) then
      print*, 'The default file name extansion is ', filex, '.'
    end if
    goto 100
  else if (file_out.eq.'ark' .or. file_out.eq.'ARK') then
    itypef=1
    goto 100
  else if (file_out.eq.'ascii' .or. file_out.eq.'ASCII') then
    itypef=2
    goto 100
  else if (file_out.eq.'ext' .or. file_out.eq.'EXT') then
110 call writen('Give new file name extension (<4 letters)>')
    read (*,'(a)',err=110, end=110) filex
    goto 100
  end if       

970 goto 990                      
                      
980 file_out='END'

990  end subroutine pmtout
                      
      
      integer function makflg(naxis, pix_flg)

        character, dimension(:,:) :: pix_flg
        integer, dimension(2) :: naxis

        naxis_pix_flg=naxis
        allocate(pix_flg_out(naxis(1),naxis(2)))
        pix_flg_out=pix_flg(1:naxis(1),1:naxis(2))

        makflg=0

      end function makflg


      subroutine makflg2(filnam)
      
        character, dimension(2880) :: relblk
        character(len=filnam_len) :: filnam
        integer :: iunit, i, iaxis1, iaxis2, icount, iblk
        character(len=80), dimension(36) :: header

        header=' '
        if (sum(naxis_pix_flg) > 0) then        
          header(1)='SIMPLE  =                    T /AN ARK_FITS FILE'
          header(2)='BITPIX  =                    8 /1 BYTE INTEGERS'
          header(3)='NAXIS   =                    2 /NUMBER OF AXES'
          header(4)=&
          'NAXIS1  =                  307 /NUMBER OF PIXELS ALONG AXIS 1'
          header(5)=&
          'NAXIS2  =                  356 /NUMBER OF PIXELS ALONG AXIS 2'
          header(6)='END'
          write(header(4)(25:30),'(i6.6)') naxis_pix_flg(1)
          write(header(5)(25:30),'(i6.6)') naxis_pix_flg(2)
        else
          header(1)='SIMPLE  =                    T /AN ARK_FITS FILE'
          header(2)='BITPIX  =                    8 /1 BYTE INTEGERS'
          header(3)='NAXIS   =                    0 /NUMBER OF AXES'
          header(4)=&
          'EXTEND  =                    T /File contains extensions'
          header(5)='END'
        end if
        
        if (next_out == 0) then
          call arkopn(iunit, filnam, ' ', 'replace', 'overwrite', &
          'unformatted', 'direct', 2880)
        else
          call arkopn(iunit, filnam, ' ', 'old', 'overwrite', &
          'unformatted', 'direct', 2880)
        end if

        if (next_out > 0) then
          header(1)="XTENSION= 'IMAGE   '           /"
          i=ext_skip(filnam, inter_out, iunit, next_out)
          inquire(iunit, nextrec=iblk)
        else
          iblk=1
        end if

        !if (debug) print*, 'Starting flag extension at block ', iblk
        write (iunit,rec=iblk) header
        icount=0
        iblk=iblk+1
        if (naxis_pix_flg(1)*naxis_pix_flg(2) > 0) then
          do iaxis2=1, naxis_pix_flg(2)
            do iaxis1=1, naxis_pix_flg(1)
              if (icount == 2880) then
                write(iunit, rec=iblk) relblk
                icount=0
                iblk=iblk+1
              end if
              icount=icount+1
              relblk(icount)=pix_flg_out(iaxis1,iaxis2)
            end do
          end do
          write (iunit, rec=iblk) relblk
        end if

        deallocate(pix_flg_out)

        close(iunit)
        
      end subroutine makflg2
      
      
      integer function inpflg(naxis, pix_flg, force_file)
      
        character, dimension(:,:), allocatable :: pix_flg
        integer, dimension(2) :: naxis
        character(len=*), optional :: force_file
        
        character, dimension(2880) :: relblk
        integer :: iunit, iaxis1, iaxis2, icount, iblk, i
        character(len=80), dimension(36) :: header
        character(len=8) :: arktyp
        logical :: there
        
        if (allocated(pix_flg)) deallocate(pix_flg)
        allocate(pix_flg(naxis(1),naxis(2)))

        if (present(force_file)) nxt_pix_file=force_file
        
        if (nxt_pix_file /= ' ') then
          call arkinq(nxt_pix_file, ' ', there, arktyp)
          if (there) then
            if (lext_in == 0) then
              print*, 'Reading pixel flag file ', trim(nxt_pix_file)
            else
              print*, 'Reading pixel flag file ', trim(nxt_pix_file), ' extension ', lext_in
            end if
            call arkopn(iunit, nxt_pix_file, ' ', 'old', 'readonly', &
            'unformatted', 'direct', 2880)
            i=ext_skip(nxt_pix_file, .false., iunit, lext_in)
            inquire(iunit, nextrec=iblk)
            read(iunit,rec=iblk) header
            icount=2880
            iblk=iblk+1
            do iaxis2=1, naxis(2)
              do iaxis1=1, naxis(1)
                if (icount == 2880) then
                  read(iunit, rec=iblk) relblk
                  icount=0
                  iblk=iblk+1
                end if
                icount=icount+1
                pix_flg(iaxis1,iaxis2)=relblk(icount)
              end do
            end do
            close(iunit)
            inpflg=1
          else
            pix_flg='O'
            inpflg=0
            print*, 'Warning, failed to find flag file ', trim(nxt_pix_file)
          end if
        else
          print*, 'Warning, no associated pixel flag file.'
          pix_flg='O'
          inpflg=0
        end if
        
        
      end function inpflg

       real function integer2(bytes)
 
        character, intent(in), dimension(2) :: bytes
 
        integer ndata
 
        ndata = ichar(bytes(2)) + 256*ichar(bytes(1))
        if (ndata > 32767) ndata=ndata-65536
        integer2=real(ndata)
 
     end function integer2

     integer function ext_skip(file, inter, iunit, skip_to)

       ! Skips to the beginning of extension skip_to.
       character(len=*), intent(in) :: file
       logical, intent(in) :: inter
       ! If the file is not open set the unit number to zero (otherwise 
       ! when fithed inquires iunit may be NaN.
       integer, intent(inout) :: iunit
       integer, intent(in) :: skip_to

       integer :: i, j, jblk, iblk, nbit, ifail, nax
       integer, dimension(2) :: naxis
       logical :: open

       character(len=80), dimension(:), allocatable :: safe_dross
       

       ext_skip=0

       if (skip_to > 0) then

          if (debug) print*, '@ Skipping to extension ', skip_to
          allocate(safe_dross(size(dross)))
          safe_dross=dross
          do j=0, skip_to-1
            if (debug) print*, '@    Extension ', j
            if (debug) print*, 'In ext_skip iunit =', iunit
            call fithed(file, inter, iunit, ifail)
            if (ifail < 0) then
              ext_skip=ifail
              return
            end if
            inquire(iunit, nextrec=iblk)
            if (debug) print*, '@    First data block ', iblk
            ! How many blocks of data?
            i=get_header_i('NAXIS', nax)
            if (nax == 0) then
              jblk=0
            else
              i=get_header_i('BITPIX', nbit)
              if (i <= 0) nbit=0
              i=get_header_i('NAXIS1', naxis(1))
              if (i <= 0) naxis(1)=0
              if (nax > 1) then
                i=get_header_i('NAXIS2', naxis(2))
                if (i <= 0) naxis(2)=0
              else
                naxis(2)=1
              end if
              nbit=naxis(1)*naxis(2)*(abs(nbit)/8)
              jblk=nbit/2880
              if (jblk*2880 /= nbit) jblk=jblk+1
              if (debug) print*, '@    Data ', nbit, ' bits and ', naxis(1), 'x', naxis(2)
            end if
            if (debug) print*, '@    Number of data blocks ', jblk
            ! Now read that block just to kick the inquire statement.
            if (debug) print*, '@ Which starts at block ', jblk+iblk
            read(iunit, rec=jblk+iblk-1)
          end do
          dross=safe_dross
          deallocate(safe_dross)
        end if
         
      end function ext_skip

      integer function wildf_ext(fildef, extdef, imext_def, last_f_e, &
        lastfil, last_iext)

        ! Does the same job as wildf, but deals with extensions.

        character(len=*) :: fildef, lastfil
        character(len=*), intent(in) :: imext_def
        character(len=*) :: extdef
        logical :: last_f_e
        integer :: last_iext

        logical :: exist
        logical, save :: last_f
        character(len=8) :: arktyp
        integer :: ifail, iostat, iblk, iunit
        integer, save :: max_ext=0, jext
        character, dimension(2880) :: test
        character(len=filnam_len), save :: lastfil_safe


        wildf_ext=0

        if (debug) print*, 'In wildf_ext, max_ext is ', max_ext

        if (max_ext == 0) then
          call wildf(fildef, extdef, last_f, lastfil_safe)
          ! Now lets find out how many extensions this new file has.
          ! Begin by assuming none.
          max_ext=0
          ! And that the next extension to be read is zero
          jext=0
          ! Find out if the file is a FITS file.
          call arkinq(lastfil_safe, extdef, exist, arktyp)
          if (arktyp == 'ARK_FITS') then
            if (imext_def == '--') then
              ! O.K., so does it have extensions?  Find this out by trying to
              ! read extension 1.  The file has not yet been opened so iunit is set to zero.
              iunit=0
              ifail=ext_skip(lastfil_safe, .false., iunit, 1)
              inquire(iunit, nextrec=iblk)
              read(iunit, rec=iblk, iostat=iostat) test
              close(iunit)
              if (iostat == 0) then
                ! O.K., the file has extensions, but non have been specified.
                wildf_ext=-1
              end if
            else if (trim(imext_def) == '*') then
              ! How many extensions are there?
              counting: do
                if (debug) print*, 'In wildf_ext iunit = ', max_ext
                iunit=0
                ifail=ext_skip(lastfil_safe, .false., iunit, max_ext+1)
                inquire(iunit, nextrec=iblk) 
                read(iunit, rec=iblk, iostat=iostat) test
                close(iunit)
                if (iostat /= 0) exit counting
                max_ext=max_ext+1
              end do counting
              close(iunit)
            else
              read(imext_def,*,iostat=iostat) max_ext
              ! And the next extension to read is this one.
              jext=max_ext
            end if
          end if
        end if

        ! The next extension to read is jext.
        last_iext=jext
        ! The next file to read is squirelled away in lastfil_safe
        lastfil=lastfil_safe
        ! Is this the last file and extension?  Start be assuming not.
        last_f_e=.false.
        ! But is this the last extension to be read?
        if (jext == max_ext) then
          ! Make sure we know next time to ask for a new file name.
          max_ext=0
          ! But will there be a next time?
          if (last_f) last_f_e=.true.
        end if
        jext=jext+1

      end function wildf_ext

end module ark_file_io
