
    character (len=*), parameter :: dirname = 'OUT'
    character*8, parameter :: storename = 'STORFFC1'
    integer, parameter :: burn_in = 50000! 55000 !Burn-in period
    integer,parameter :: nsample_widening=400000! 50000!Post burn-in
    integer,parameter :: burn_in_widening=100000! 50000!Post burn-in

    integer, parameter :: thin = 250    !Thinning of the chain

    integer, parameter :: Scratch = 1     ! 0: Start from Stored model 1: Start from scratch
    integer, parameter :: store = 99999999    !Store models every "store" iteration.

    ! Each chain is run for 'burn_in + nsample' steps in total. The first burn-in samples are discarded as burn-in steps, only after which the sampling algorithm is assumed to have converged. To eliminate dependent samples in the ensemble solution, every thinn model visited in the second part is selected for the ensemble. The convergence of the algorithm is monitored with a number of indicators such as acceptance rates, and sampling efficiency is optimized by adjusting the variance of the Gaussian proposal functions
    !------------------------------------------------
    ! Prior distribution (Bounds odf the model space)
    !------------------------------------------------

    !depth
    real, parameter :: d_min = 0   ! depth bounds
    real, parameter :: d_max = 800

    real, parameter :: width = 0.2 ! width of the prior in vsv

    real, parameter :: vp_min = -0.4 ! bounds of the prior in vp/vs
    real, parameter :: vp_max = 0.4

    real, parameter :: xi_min = 0.6 ! bounds of the prior in xi
    real, parameter :: xi_max = 1.4

    double precision, parameter ::    Ad_R_max = 100 ! bounds of the prior in Ad_R - the error parameter for rayleigh wave velocity
    double precision, parameter ::    Ad_R_min = 0.001

    double precision, parameter ::    Ad_L_max = 200 ! bounds of the prior in Ad_L
    double precision, parameter ::    Ad_L_min = 0.001

    !-----------------------------------------
    ! Sdt for Proposal distributions
    !-----------------------------------------

    ! The convergence of the algorithm is monitored with a number of indicators such as
    ! acceptance rates, and sampling efficiency is optimized by adjusting the variance of
    ! the Gaussian proposal functions

    ! These values have to be "tuned" so the acceptance rates written in OUT/mpi.out
    ! are as close as possible to 44%. This determinde the efficiency of posteriro sampling. !  If AR larger than 44%, increase the Sdt for less Acceptance.
    ! If AR_* smaller than 44%, decrease the Sdt for more
    real, parameter :: perturb = 0.35  ! perturbation of proposal when adjusting acceptance rates
    integer, parameter :: every = 1001 ! we do something every 'every' ??
    integer, parameter :: switch_sigma = 10

    ! for plotting, legacy to check old code
    real,parameter :: prof=d_max
    integer,parameter :: disd=50
    integer,parameter :: disA=50
    integer,parameter :: disv=50

    !--------------------------------------------
    ! Parameters for Displaying results
    !--------------------------------------------

    integer, parameter :: display = 10000 ! display results in OUT/mpi.out
    !every display samples

    !parameters for minos
    real, parameter :: eps=1e-3 !precision of runge-kutta, as high as possible for speed
    real, parameter :: wgrav=1  !minimal frequency for gravitational effects, very low for speed
    integer, parameter :: lmin=1 !min and max mode numbers (constrained by periods anyway)
    integer, parameter :: lmax=6000
    integer, parameter :: nmodes_max=10000 !max number of modes
    integer, parameter :: nharmo_max=6 !max number of harmonics

    ! parameters for joint inversion
    integer, parameter :: numdis_max=16200
    real, parameter :: logalpha_min=-100
    real, parameter :: logalpha_max=5
    integer, parameter :: num_logalpha=200
    real, parameter :: widening_start=4.
    integer, parameter :: n_w=4
    real,parameter :: widening_step=-1.

    integer,parameter :: everyall=10000

    ! testing
    logical, parameter :: testing=.false.
    real, parameter :: err_level=0.04
