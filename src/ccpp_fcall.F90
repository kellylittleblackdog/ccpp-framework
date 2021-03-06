!>
!! @brief The CCPP function call module.
!!
!! @details The CCPP routines for calling the specified
!!          physics group/subcyce/scheme.
!
module ccpp_fcall

    use, intrinsic :: iso_c_binding,                                   &
                      only: c_int32_t, c_char, c_ptr, c_loc, c_funptr
    use            :: ccpp_types,                                      &
                      only: ccpp_t, ccpp_suite_t, ccpp_group_t,        &
                            ccpp_subcycle_t, ccpp_scheme_t,            &
                            CCPP_STAGES, CCPP_DEFAULT_STAGE
    use            :: ccpp_errors,                                     &
                      only: ccpp_error, ccpp_debug
    use            :: ccpp_strings,                                    &
                      only: ccpp_cstr
    use            :: ccpp_dl,                                         &
                      only: ccpp_dl_call

    implicit none

    private
    public :: ccpp_physics_init, ccpp_physics_run, ccpp_physics_finalize

    contains

    !!
    !! Public CCPP physics init/run/finalize routines
    !!

    !>
    !! Single entry point for initializing ccpp physics.
    !!
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_physics_init(cdata, ierr)

        type(ccpp_t),     target,   intent(inout) :: cdata
        integer,                    intent(out)   :: ierr

        ! Local variables
        type(ccpp_scheme_t)   :: scheme

        ierr = 0
        call ccpp_debug('Called ccpp_physics_init')

        ! Run the suite init scheme before the individual init schemes
        if (allocated(cdata%suite%init%name)) then
            scheme = cdata%suite%init
            call ccpp_run_scheme(scheme, cdata, stage='init', ierr=ierr)
        end if

        call ccpp_run_suite(cdata%suite, cdata, stage='init', ierr=ierr)

    end subroutine ccpp_physics_init

    !>
    !! Single entry point for running ccpp physics.
    !! Optional arguments specify whether to run one
    !! group, subcycle or an individual scheme of the
    !! suite. If no optional arguments are provided,
    !! the entire suite attached to cdata is run.
    !!
    !! The optional argument subcycle requires group;
    !! group and scheme are mutually exclusive.
    !!
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[in    ] group    The group of physics to run (optional)
    !! @param[in    ] subcycle The subcycle of a group of physics to run (optional)
    !! @param[in    ] scheme   The name of a single scheme to run (optional)
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_physics_run(cdata, group_name, subcycle_count, scheme_name, ierr)

        type(ccpp_t),     target,   intent(inout) :: cdata
        character(len=*), optional, intent(in)    :: group_name
        integer,          optional, intent(in)    :: subcycle_count
        character(len=*), optional, intent(in)    :: scheme_name
        integer,                    intent(out)   :: ierr

        ! Local variables
        type(ccpp_suite_t)   , pointer :: suite
        type(ccpp_group_t)   , pointer :: group
        type(ccpp_subcycle_t), pointer :: subcycle
        type(ccpp_scheme_t)  , pointer :: scheme

        ierr = 0
        call ccpp_debug('Called ccpp_physics_run')

        ! Consistency checks
        if (present(group_name) .and. present(scheme_name)) then
            call ccpp_error('Logic error in ccpp_physics_run: group_name and scheme_name are mutually exclusive')
            ierr = 1
            return
        else if (present(subcycle_count) .and. .not. present(group_name)) then
            call ccpp_error('Logic error in ccpp_physics_run: subcycle_count requires optional argument group_name')
            ierr = 1
            return
        end if

        suite => cdata%suite

        if (present(group_name)) then
            ! Find the group to run from the suite
            group => ccpp_find_group(suite, group_name, ierr=ierr)
            if (ierr/=0) return
            if (present(subcycle_count)) then
                ! Find the subcycle to run in the current group
                subcycle => ccpp_find_subcycle(group, subcycle_count, ierr=ierr)
                if (ierr/=0) return
                call ccpp_run_subcycle(subcycle, cdata, ierr=ierr)
            else
                call ccpp_run_group(group, cdata, ierr=ierr)
            end if
        else if (present(scheme_name)) then
            ! Find the scheme to run from the suite
            scheme => ccpp_find_scheme(suite, scheme_name, ierr=ierr)
            if (ierr/=0) return
            call ccpp_run_scheme(scheme, cdata, ierr=ierr)
        else
            ! If none of the optional arguments is present, run the entire suite
            call ccpp_run_suite(suite, cdata, ierr=ierr)
        end if

    end subroutine ccpp_physics_run

    !>
    !! Single entry point for finalizing ccpp physics.
    !!
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_physics_finalize(cdata, ierr)

        type(ccpp_t),     target,   intent(inout) :: cdata
        integer,                    intent(out)   :: ierr

        ! Local variables
        type(ccpp_scheme_t)   :: scheme

        ierr = 0
        call ccpp_debug('Called ccpp_physics_finalize')

        call ccpp_run_suite(cdata%suite, cdata, stage='finalize', ierr=ierr)

        ! Run the suite finalize scheme after the individual finalize schemes
        if (allocated(cdata%suite%finalize%name)) then
            scheme = cdata%suite%finalize
            call ccpp_run_scheme(scheme, cdata, stage='finalize', ierr=ierr)
        end if

    end subroutine ccpp_physics_finalize

    !!
    !! Private/internal routines for running suites, groups, subcycles and schemes *DH
    !!

    !>
    !! The run subroutine for a suite. This will call
    !! the all groups within a suite.
    !!
    !! @param[in    ] suite    The suite to run
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[in    ] stage    The stage for which to run the suite
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_run_suite(suite, cdata, stage, ierr)

        type(ccpp_suite_t),    intent(inout)          :: suite
        type(ccpp_t), target,  intent(inout)          :: cdata
        character(len=*),      intent(in),   optional :: stage
        integer,               intent(  out)          :: ierr

        integer                               :: i

        ierr = 0

        call ccpp_debug('Called ccpp_run_suite')

        do i=1,suite%groups_max
            call ccpp_run_group(suite%groups(i), cdata, stage=stage, ierr=ierr)
            if (ierr /= 0) then
                return
            end if
        end do

    end subroutine ccpp_run_suite

    !>
    !! The find subroutine for a group. This will return
    !! the group that matches group_name and ierr=0,
    !! or ierr=1 if no such group is found.
    !!
    !! @param[in   ] suite      The suite in which to find the group
    !! @param[in   ] group_name The name of the group to run
    !! @param[  out] ierr       Integer error flag
    !
    function ccpp_find_group(suite, group_name, ierr) result(group)

        type(ccpp_suite_t), target, intent(in   ) :: suite
        character(len=*),           intent(in   ) :: group_name
        integer,                    intent(  out) :: ierr
        type(ccpp_group_t), pointer               :: group

        integer :: i

        call ccpp_debug('Called ccpp_find_group')

        ierr = 0
        do i=1, suite%groups_max
            if (trim(suite%groups(i)%name) .eq. trim(group_name)) then
                call ccpp_debug('Group ' // trim(group_name) // ' found in suite')
                group => suite%groups(i)
                return
            end if
        end do

        call ccpp_error('Group ' // trim(group_name) // ' not found in suite')
        ierr = 1

    end function ccpp_find_group

    !>
    !! The run subroutine for a group. This will call
    !! the all subcycles within a group.
    !!
    !! @param[in    ] group    The group to run
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[in    ] stage    The stage for which to run the group
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_run_group(group, cdata, stage, ierr)

        type(ccpp_group_t),    intent(inout)          :: group
        type(ccpp_t), target,  intent(inout)          :: cdata
        character(len=*),      intent(in),   optional :: stage
        integer,               intent(  out)          :: ierr

        integer                               :: i

        ierr = 0

        call ccpp_debug('Called ccpp_run_group')

        do i=1,group%subcycles_max
            call ccpp_run_subcycle(group%subcycles(i), cdata, stage=stage, ierr=ierr)
            if (ierr /= 0) then
                return
            end if
        end do

    end subroutine ccpp_run_group

    !>
    !! The find subroutine for a subcycle. This will return
    !! the subcycle that matches subcycle_count in the group
    !! and ierr==0, or ierr==1 if no such subcycle is found.
    !!
    !! @param[in   ] group          The group in which to find the subcycle
    !! @param[in   ] subcycle_count The name of the subcycle to run
    !! @param[  out] ierr           Integer error flag
    !
    function ccpp_find_subcycle(group, subcycle_count, ierr) result(subcycle)

        type(ccpp_group_t),    target, intent(in   ) :: group
        integer,                       intent(in   ) :: subcycle_count
        integer,                       intent(  out) :: ierr
        type(ccpp_subcycle_t), pointer               :: subcycle

        call ccpp_debug('Called ccpp_find_subcycle')

        ierr = 0

        if (subcycle_count <= group%subcycles_max) then
            call ccpp_debug('Subcycle found in group ' // trim(group%name))
            subcycle => group%subcycles(subcycle_count)
            return
        end if

        call ccpp_error('Subcycle not found in group ' // trim(group%name))
        ierr = 1

    end function ccpp_find_subcycle

    !>
    !! The run subroutine for a subcycle. This will call
    !! the all schemes within a subcycle. It will also
    !! loop if the loop attribut is greater than 1.
    !!
    !! @param[in    ] subcycle The subcycle to run
    !! @param[in,out] cdata    The CCPP data of type ccpp_t
    !! @param[in    ] stage    The stage for which to run the subcycle
    !! @param[   out] ierr     Integer error flag
    !
    subroutine ccpp_run_subcycle(subcycle, cdata, stage, ierr)

        type(ccpp_subcycle_t), intent(inout)          :: subcycle
        type(ccpp_t), target,  intent(inout)          :: cdata
        character(len=*),      intent(in),   optional :: stage
        integer,               intent(  out)          :: ierr

        integer                               :: i
        integer                               :: j

        ierr = 0

        call ccpp_debug('Called ccpp_run_subcycle')

        do i=1,subcycle%loop
            do j=1,subcycle%schemes_max
                call ccpp_run_scheme(subcycle%schemes(j), cdata, stage=stage, ierr=ierr)
                if (ierr /= 0) then
                    return
                end if
            end do
        end do

    end subroutine ccpp_run_subcycle

    !>
    !! The find subroutine for a scheme. This will return
    !! the scheme that matches scheme_name and ierr==0,
    !! or ierr==1 if no such scheme is found.
    !!
    !! @param[in   ] suite       The suite in which to find the scheme
    !! @param[in   ] scheme_name The name of the scheme to run
    !! @param[  out] ierr        Integer error flag
    !
    function ccpp_find_scheme(suite, scheme_name, ierr) result(scheme)

        type(ccpp_suite_t),  target, intent(in   ) :: suite
        character(len=*),            intent(in   ) :: scheme_name
        integer,                     intent(  out) :: ierr
        type(ccpp_scheme_t), pointer               :: scheme

        integer :: i, j, k

        call ccpp_debug('Called ccpp_find_scheme')

        ierr = 0
        do i=1, suite%groups_max
            do j=1, suite%groups(i)%subcycles_max
                do k=1, suite%groups(i)%subcycles(j)%schemes_max
                    if (trim(suite%groups(i)%subcycles(j)%schemes(k)%name) .eq. trim(scheme_name)) then
                        call ccpp_debug('Scheme ' // trim(scheme_name) // ' found in suite')
                        scheme => suite%groups(i)%subcycles(j)%schemes(k)
                        return
                    end if
                end do
            end do
        end do

        call ccpp_error('Scheme ' // trim(scheme_name) // ' not found in suite')
        ierr = 1

    end function ccpp_find_scheme

    !>
    !! The run subroutine for a scheme. This will call
    !! the single scheme specified.
    !!
    !! @param[in    ] scheme  The scheme to run
    !! @param[in,out] cdata   The CCPP data of type ccpp_t
    !! @param[in    ] stage   The stage for which to run the scheme
    !! @param[   out] ierr    Integer error flag
    !
    subroutine ccpp_run_scheme(scheme, cdata, stage, ierr)

        type(ccpp_scheme_t),  intent(in   )          :: scheme
        type(ccpp_t), target, intent(inout)          :: cdata
        character(len=*),     intent(in),   optional :: stage
        integer,              intent(  out)          :: ierr

        character(:), allocatable      :: stage_local
        character(:), allocatable      :: function_name
        integer :: l

        ierr = 0

        if (present(stage)) then
            stage_local = trim(stage)
        else
            stage_local = trim(CCPP_DEFAULT_STAGE)
        end if

        call ccpp_debug('Called ccpp_run_scheme for ' // trim(scheme%name) &
                        //' in stage ' // trim(stage_local))

        function_name = trim(scheme%get_function_name(stage_local))

        do l=1,scheme%functions_max
            associate (f=>scheme%functions(l))
            if (trim(function_name) == trim(f%name)) then
                ierr = ccpp_dl_call(f%function_hdl, c_loc(cdata))
                if (ierr /= 0) then
                    call ccpp_error('A problem occured calling '// trim(f%name) &
                                    //' of scheme ' // trim(scheme%name) &
                                    //' in stage ' // trim(stage_local))
                end if
                ! Return after calling the scheme, with or without error
                return
            end if
            end associate
        end do

        ! If we reach this point, the required function was not found
        ierr = 1
        do l=1,size(CCPP_STAGES)
            if (trim(stage_local) == trim(CCPP_STAGES(l))) then
                ! Stage is valid --> problem with the scheme
                call ccpp_error('Function ' // trim(function_name)   &
                                //' of scheme ' // trim(scheme%name) &
                                //' for stage ' // trim(stage_local) &
                                //' not found in suite')
                return
            end if
        end do
        ! Stage is invalid
        call ccpp_error('Invalid stage ' // trim(stage_local) &
                        //' requested in ccpp_run_scheme')

    end subroutine ccpp_run_scheme

#if 0
    ! DH 20180504 - keep for future use
    !>
    !! The run subroutine for a function pointer. This
    !! will call the single function specified.
    !!
    !! @param[in    ] scheme  The scheme to run
    !! @param[in,out] cdata   The CCPP data of type ccpp_t
    !! @param[   out] ierr    Integer error flag
    !
    subroutine ccpp_run_fptr(fptr, cdata, ierr)

        type(c_ptr),          intent(in   )  :: fptr
        type(ccpp_t), target, intent(inout)  :: cdata
        integer,              intent(  out)  :: ierr

        ierr = 0

        call ccpp_debug('Called ccpp_run_fptr')

        ierr = ccpp_dl_call(fptr, c_loc(cdata))
        if (ierr /= 0) then
            call ccpp_error('A problem occured calling function pointer')
        end if

    end subroutine ccpp_run_fptr
#endif

end module ccpp_fcall
