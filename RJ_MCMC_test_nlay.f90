!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! This program does a Transdimensional inversion of Surface wave dispersion curves
! with the reversible jump algorithm

! Thomas Bodin, ANU, December 2011
!*********************************************************************
!/////////////////////////////////////////////////////////////////////
!********************************************************************

program RJ_MCMC

    use mpi
    implicit none
    ! include 'mpif.h'
    include 'params.h'
    include 'params_p.h'
    !             ----------------------------------
    !             BEGINING OF THE USER-DEFINED PARAMETERS
    !             ----------------------------------

    !-----------------------------------------
    ! Parameters of the Markov chain
    !-----------------------------------------
    ! 1 Constrain using PsPp data, 0 leave it out.
    integer, parameter :: PsPp_flag = 0

    ! 0 let Vp Free, 1 Scale Vp, 2 Fix Vp to ref.
    integer, parameter :: vp_flag = 0                  
    ! scaling parameter for vph in voro when vp_flag=1
    ! dvp=dvs*vp_scale, when vp_scale<=1.0
    ! For S40RTS scaling dvp = dvs * 1.0/(depth/2891.0+2.0), when vp_scale>1.0
    real, parameter :: vp_scale = 2.0                    

    character (len=*), parameter :: mods_dirname = 'MODS_OUT_TEST' ! This is where output info files are saved and input data files are taken.
    real, parameter :: noise_dspd = 0.01                            ! Gaussian noise added to disp data (>0). twice for Love.
    real, parameter :: obs_err_R = 0.04                             ! Observational errors - obs_err_R*Ad_R=noise_dspd_R (sigma_R)
    real, parameter :: obs_err_L = 0.04                             ! Observational errors - obs_err_L*Ad_L=noise_dspd_L (sigma_L)

    character(len=64), parameter :: rp_file = 'rayp2.in'
    real, parameter :: noise_PsPp = 0.05                             ! Gaussian noise added to travel time data (>0)
    real, parameter :: obs_err_PsPp = 0.2                             ! Observational errors - obs_err_PsPp*Ad_PsPp=noise_PsPp (sigma_PsPp)

    character (len=*), parameter :: dirname = 'OUT_TEST' ! This is where output info files are saved and input data files are taken.
    character*8, parameter :: storename = 'STORFFC1'     ! This is where output models are saved
    integer, parameter :: burn_in = 200000 ! 55000 !Burn-in period
    integer, parameter :: nsample = 200000 ! 50000!Post burn-in
    integer, parameter :: thin = 50    !Thinning of the chain 

    integer, parameter :: Scratch = 1     ! 0: Start from Stored model 1: Start from scratch
    integer, parameter :: store = 999999999    !Store models every "store" iteration. 

    ! Each chain is run for 'burn_in + nsample' steps in total. The first burn-in samples are discarded as burn-in steps, only after which the sampling algorithm is assumed to have converged. To eliminate dependent samples in the ensemble solution, every thin model visited in the second part is selected for the ensemble. The convergence of the algorithm is monitored with a number of indicators such as acceptance rates, and sampling efficiency is optimized by adjusting the variance of the Gaussian proposal functions 

    !------------------------------------------------
    ! Prior distribution (Bounds of the model space)
    !------------------------------------------------

    !depth
    real, parameter :: d_min = 0   ! depth bounds  
    real, parameter :: d_max = 700 
      
    real, parameter :: width = 0.4 ! width of the prior in vsv
    
    real, parameter :: vp_min = -0.4
    real, parameter :: vp_max = 0.4 ! bounds of the prior in vp

    real, parameter :: xi_min = 0.6 ! bounds of the prior in xi
    real, parameter :: xi_max = 1.4

    double precision, parameter ::    Ad_R_max = 25 ! bounds of the prior in Ad_R - the error parameter for rayleigh wave velocity
    double precision, parameter ::    Ad_R_min = 0.0000002

    double precision, parameter ::    Ad_L_max = 25 ! bounds of the prior in Ad_L
    double precision, parameter ::    Ad_L_min = 0.0000002

    !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
    double precision, parameter ::    Ad_PsPp_max = 25 ! bounds of the prior in Ad_PsPp
    double precision, parameter ::    Ad_PsPp_min = 0.0000002

    !!!!!!!!!!!!!!! Add a prior for starting models close to PREM !!!!!!!!!!!!!!!!!
    real, parameter :: sp_width = 0.4 ! width of the prior in vsv
    real, parameter :: sp_vp_min = -0.4
    real, parameter :: sp_vp_max = 0.4 ! bounds of the prior in vp
    real, parameter :: sp_xi_min = 0.6 ! bounds of the prior in xi
    real, parameter :: sp_xi_max = 1.4
    real, parameter :: sp_malay = 80
    double precision, parameter ::    sp_Ad_R_max = 25 ! bounds of the prior in Ad_R - the error parameter for rayleigh wave velocity
    double precision, parameter ::    sp_Ad_L_max = 25 ! bounds of the prior in Ad_L
    double precision, parameter ::    sp_Ad_PsPp_max = 25 ! bounds of the prior in Ad_PsPp


    !-----------------------------------------
    ! Sdt for Proposal distributions
    !-----------------------------------------

    ! The convergence of the algorithm is monitored with a number of indicators such as
    ! acceptance rates, and sampling efficiency is optimized by adjusting the variance of
    ! the Gaussian proposal functions 

    ! These values have to be "tuned" so the acceptance rates written in OUT/mpi.out
    ! are as close as possible to 44%. This determines the efficiency of posterior sampling. !  If AR larger than 44%, increase the Sdt for less Acceptance.
    ! If AR_* smaller than 44%, decrease the Sdt for more
    real, parameter :: perturb = 0.35  ! standard deviation (I guess)
    integer, parameter :: every = 1001 ! we do something every 'every' ?? This is a 'KICK' to get it moving.
    integer, parameter :: switch_sigma = 10 ! swap between sigma_vsv, sigma_vp optimisation every X iterations
    !--------------------------------------------
    ! Parameters for Displaying results 
    !-------------------------------------------- 

    integer, parameter :: display = 1000 ! display results in OUT/mpi.out 
    !every display samples

     !discretezation for the posterior distribution.
     !specifies the number of velocity pixels in (Vs, depth)
     !This is because the solution is visualized as an histogram, 
     !and hence we need to define the number of bins

    integer, parameter :: disd = 200 !depth
    integer, parameter :: disv = 100 !velocity/anisotropy
    integer, parameter :: disA = 200 !for noise parameter 

    !depth of model for display
    real, parameter :: prof = d_max
    
    !parameters for minos
    real, parameter :: eps=1e-3 !precision of runge-kutta, as high as possible for speed
    real, parameter :: wgrav=1  !minimal frequency for gravitational effects, very low for speed
    integer, parameter :: lmin=1 !min and max mode numbers (constrained by periods anyway) 
    integer, parameter :: lmax=6000
    integer, parameter :: nmodes_max=10000 !max number of modes
    integer, parameter :: nharmo_max=6 !max number of harmonics

    !***************************************************************

    ! DECLARATIONS OF VARIABLES

    !****************************************************************

    real , EXTERNAL    ::    gasdev,ran3,interp, vp_scale_S40 ! Functions for random variables and interpolation.
    real log, sqrt

    integer i,ii,sample,ind,th,ount,k ! various indices
    integer nlims_cur,nlims_cur_diff
    logical ier, error_flag ! error flags for dispersion curves and minos_bran
    integer npt,npt_prop,npt_iso,npt_ani ! numbers of points, isotropic, anisotropic
    logical accept,tes,birth,birtha,death,deatha,move,value,noisd_R,noisd_L,ani,change_vp !which parameter did we change?
    logical testing
    integer ind2,ind_vp,ind_vsv,ind_xi,j !more indices, mostly for posterior. j sometimes is the number of processors, careful at the end!
    real d !for calculating posterior, mostly depth
    real histo(maxlay),histos(maxlay),histoch(disd),histochs(disd) ! histo of layers, changepoints 
    real avvs(disd),avvp(disd),avxi(disd),avxis(disd),avvss(disd),avvps(disd) ! average of posterior
    real peri_R(ndatadmax),peri_L(ndatadmax) !periods of data
    real peri_R_tmp(ndatadmax),peri_L_tmp(ndatadmax) !periods of data
    real postvp(disd,disv),postvs(disd,disv),postxi(disd,disv),postvps(disd,disv),postvss(disd,disv),postxis(disd,disv) ! posteriors
    real probani(disd),probanis(disd) !anisotropy probabilities
    integer n_R(ndatadmax),n_L(ndatadmax),nmax_R,nmax_L,nmin_R,nmin_L !harmonic number of modes
    integer n_R_tmp(ndatadmax),n_L_tmp(ndatadmax)
    integer nlims_R(2,nharmo_max),nlims_L(2,nharmo_max),numharm_count,numharm_R(nharmo_max),numharm_L(nharmo_max)
    real PrB,AcB,PrD,AcD,Prnd_R,Acnd_R,Prnd_L,Acnd_L,&
        Acba,Prba,Acda,Prda,out,Prxi,Acxi,Pr_vp,&
        Ac_vp !,PrP(2),PrV(2),AcP(2),AcV(2) ! to adjust acceptance rates for all different parameters
    real PrP,PrV,AcP,AcV
    real lsd_L,lsd_L_prop,lsd_L_min,lsd_R,lsd_R_prop,lsd_R_min !logprob without uncertainties
    real logprob_vsv,logprob_vp !for reversible jump
    real convAd_R(nsample+burn_in),convAd_Rs(nsample+burn_in),convAd_L(nsample+burn_in),convAd_Ls(nsample+burn_in) !variations of uncertainty parameters
    real voro(malay,4),vsref_min,vsref_max,vpref_min,vpref_max !the model with its bounds
    real voro_prop(malay,4),ncell(nsample+burn_in),convd_R(nsample+burn_in),convd_L(nsample+burn_in),&
        convd_Rs(nsample+burn_in),convd_Ls(nsample+burn_in) ! the proposed model, history of lsd
    real ncells(nsample+burn_in),t1,t2 !timers, history of ls
    real like,like_prop,u,& !log-likelihoods
        liked_R_prop,liked_R,liked_L_prop,liked_L
    real ML_Ad_R(disA),ML_Ad_Rs(disA),TRA(malay,malay+1),& !histogram of uncertainty parameters
        TRAs(malay,malay+1),ML_Ad_L(disA),ML_Ad_Ls(disA)
    double precision logrsig,Ad_R,Ad_R_prop,Ad_L,Ad_L_prop !uncertainty parameters
    real sigmav,sigmav_old,sigmav_new,AR_birth_old   !proposal on velocity when Birth move  
    real sigmavp,sigmavp_old,sigmavp_new       !proposal on vp when Birth move
    integer sigma_count                              ! Count Sigmav & sigmavp perturbations
    real d_obsdcR(ndatadmax),d_obsdcL(ndatadmax),d_obsdcRe(ndatadmax),d_obsdcLe(ndatadmax) !observed data
    real inorout(21000),inorouts(21000)
    integer members(21000),io ! mpi related variables
    integer ndatad_R,ndatad_L,ndatad_R_tmp,ndatad_L_tmp !number of observed data points
    real pxi,p_vp,pd1,pv1,pd2,pv2,pAd_R,pAd_L ! related to observed data for azimuthal anisotropy
    ! Geometry parameters
    ! Traces
    integer nptref,malayv ! number of points in reference model, number of layers in voro
    real convBs(nsample+burn_in),convB(nsample+burn_in),convPs(nsample+burn_in),convP(nsample+burn_in) ! birth rates, vp change rates
    real convvs1(nsample+burn_in),convvs1s(nsample+burn_in),convvs2(nsample+burn_in),convvs2s(nsample+burn_in)
    real convdp1(nsample+burn_in),convdp1s(nsample+burn_in),convdp2(nsample+burn_in),convdp2s(nsample+burn_in)
    real convvp(nsample+burn_in),convvps(nsample+burn_in),convxis(nsample+burn_in),convxi(nsample+burn_in)
    real convBas(nsample+burn_in),convBa(nsample+burn_in) ! anisotropic birth rates
    real convDs(nsample+burn_in),convD(nsample+burn_in),convDas(nsample+burn_in),convDa(nsample+burn_in)

    logical isoflag(malay),isoflag_prop(malay) ! is this layer isotropic?
    real d_cR(ndatadmax),d_cL(ndatadmax) ! phase velocity as simulated by forward modelling
    real d_cR_tmp(ndatadmax),d_cL_tmp(ndatadmax)
    real rq_R(ndatadmax),rq_L(ndatadmax) ! errors from modelling
    real d_cR_prop(ndatadmax),d_cL_prop(ndatadmax) ! phase velocity as simulated by forward modelling
    real d_cR_prop_tmp(ndatadmax),d_cL_prop_tmp(ndatadmax) ! phase velocity as simulated by forward modelling
    real rq_R_prop(ndatadmax),rq_L_prop(ndatadmax)
    !for MPI
    integer ra,ran,rank, nbproc, ierror ,status(MPI_STATUS_SIZE),group_world,good_group,MPI_COMM_small,flag
    ! ierror: MPI-related error status, nbproc: MPI-related, number of processes, rank, group_world: MPI-related
    character filename*13, number*4
    real likemax ! log-likelihood of best model
    integer nptmax ! number of layers of the best model
    real voromax(malay,4) ! best model
    character filenamemax*30  !filename for writing the best model
    real d_cRmoy(ndatadmax), d_cRmoys(ndatadmax), d_cLmoy(ndatadmax), d_cLmoys(ndatadmax) ! average dispersion curve
    real d_cRdelta(ndatadmax), d_cRdeltas(ndatadmax), d_cLdelta(ndatadmax), d_cLdeltas(ndatadmax) ! standart deviation of dispersion curve
    real model_ref(mk,9) ! reference model, all models are deviations from it
    real,dimension(mk) :: r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,xi,vp_data,vs_data ! input for forward modelling
    integer :: nptfinal,nic,noc,nic_ref,noc_ref,jcom ! more inputs
    integer :: nmodes,n_mode(nmodes_max),l_mode(nmodes_max) ! outputs of forward modelling
    real :: c_ph(nmodes_max),period(nmodes_max),raylquo(nmodes_max),tref ! more outputs, rayquo: error measurement, should be of the order of eps
    real :: wmin_R(nharmo_max),wmax_R(nharmo_max),wmin_L(nharmo_max),wmax_L(nharmo_max) ! more inputs for forward modelling
    integer :: recalculated !counts the number of times we need to improve eps
    logical :: stuck
    integer :: nharm_R,nharm_L,iharm
    real :: dummy_d_obsdcR(ndatadmax), dummy_d_obsdcL(ndatadmax)
    !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
    real, dimension (nrays_max) :: rayp, d_obsPsPp, d_obsPsPpe, d_PsPp, d_obsPsPp_prop, d_PsPp_prop
    integer :: nrays
    logical :: PsPp_error, noisd_PsPp
    real :: lsd_PsPp, liked_PsPp, lsd_PsPp_min, liked_PsPp_prop, lsd_PsPp_prop
    double precision Ad_PsPp, Ad_PsPp_prop
    real :: pAd_PsPp, Prnd_PsPp,Acnd_PsPp
    real convAd_PsPp(nsample+burn_in),convAd_PsPps(nsample+burn_in) !variations of uncertainty parameters
    real convd_PsPp(nsample+burn_in), convd_PsPps(nsample+burn_in) 
    real ML_Ad_PsPp(disA),ML_Ad_PsPps(disA)!histogram of uncertainty parameters
    real d_PsPpmoy(nrays_max), d_PsPpdelta(nrays_max), d_PsPpmoys(nrays_max), d_PsPpdeltas(nrays_max)
    real,dimension(4) :: t

    ! For saving all models
    integer th_all
    integer, parameter :: everyall = 5000
    character filebycore*15

    ! todo: implement a test with raylquo
1000 format(I4)

    !***********************************************************************

    CALL cpu_time(t1)  !Tic. start counting time 
 
    !Start Parralelization of the code. From now on, the code is run on each
    !processor independently, with ra = the number of the proc.

    !-!
    call MPI_INIT(ierror)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, nbproc, ierror) ! MPI_COMM_WORLD: communicator (https://www.open-mpi.org/doc/v4.0/man3/MPI_Comm_size.3.php)
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierror) ! https://www.open-mpi.org/doc/v4.0/man3/MPI_Comm_rank.3.php
    call MPI_Comm_group(MPI_COMM_WORLD,group_world,ierror) ! https://www.open-mpi.org/doc/v3.0/man3/MPI_Comm_group.3.php
    
    write(*,*)dirname
    
    pxi = 0.4             ! proposal for change in xi
    p_vp = 0.1           ! proposal for change in vp
    pd1 = 10! 0.2         ! proposal on change in position  
    pv1 = 0.1! 0.04     ! proposal on velocity
    pAd_R = 0.5        ! proposal for change in R noise
    pAd_L = 0.5        ! proposal for change in L noise
    sigmav=0.15        ! proposal for vsv when creating a new layer
    sigmavp=0.15     ! proposal for vp when creating a new layer
    if (PsPp_flag==1) then
        pAd_PsPp = 0.5        ! proposal for change in PsPp tdiff noise
    end if

    testing=.false.
    if (testing) write(*,*)'testing with synthetic model'
    ! write(*,*)'testing',maxrq
    ra=rank !seed for RNG
    ran=rank
    inorout=0
    inorouts=0
    postxi=0
    postxis=0
    postvp=0
    postvps=0
    postvs=0
    postvss=0
    avvs=0
    avvp=0
    avxi=0
    avvss=0
    avvps=0
    avxis=0
 
    lsd_R=0
    lsd_L=0
    histoch=0
    histochs=0
    ML_Ad_R=0
    ML_Ad_Rs=0
    ML_Ad_L=0
    ML_Ad_Ls=0
    probani=0
    probanis=0
    
    ncell=0
    ncells=0
    convd_R=0
    convd_L=0
    convd_Rs=0
    convd_Ls=0
    convB=0
    convBs=0
    convBa=0
    convBas=0
    convD=0
    convDs=0
    convvs1=0
    convvs1s=0
    convvs2=0
    convvs2s=0
    convdp1=0
    convdp1s=0
    convdp2=0
    convdp2s=0
    convDa=0
    convDas=0
    convP=0
    convPs=0
    histo=0
    histos=0
    convAd_R=0
    convAd_Rs=0
    convAd_L=0
    convAd_Ls=0
    TRA=0
    TRAs=0
    d_cRmoy=0
    d_cLmoy=0
    d_cRmoys=0
    d_cLmoys=0
    d_cRdelta=0
    d_cLdelta=0
    d_cRdeltas=0
    d_cLdeltas=0 

    if (PsPp_flag==1) then
        ML_Ad_PsPp=0
        ML_Ad_PsPps=0
        convAd_PsPp=0
        convAd_PsPps=0
        d_PsPpmoy=0
        d_PsPpdelta=0
    end if

    ier=.false.

    !************************************************************
    !                READ PREM 
    !************************************************************
    ! open(7,file="Model_PREM_SIMPLE.in",status='old',form='formatted')
    ! !  110 format(20a4)
    ! read(7,*) nptref,nic_ref,noc_ref
    ! read(7,'(f8.0, 3f9.2, 2f9.1, 2f9.2, f9.5)') (model_ref(i,1),&
    !     model_ref(i,2),model_ref(i,3),model_ref(i,4),model_ref(i,5),&
    !     model_ref(i,6),model_ref(i,7),model_ref(i,8),model_ref(i,9),&
    !     i=1,nptref)
    ! close(7)

    open(7,file="Model_PREM_DISC_20.in",status='old',form='formatted')
    read(7,*) nptref,nic_ref,noc_ref
    do i = 1,nptref
         read(7,*) model_ref(i,1),&
                    model_ref(i,2),model_ref(i,3),model_ref(i,4),model_ref(i,5),&
                    model_ref(i,6),model_ref(i,7),model_ref(i,8),model_ref(i,9)
    end do
    close(7)

    j=1
    do while (model_ref(j,1)<rearth-d_max*1000.)
        j=j+1
    end do
    j=j-1
    
    vsref_min=minval(model_ref(j:nptref,4)*(1-width)) ! setting min/max vsv velocities for writing later
    vsref_max=maxval(model_ref(j:nptref,4)*(1+width))
    
    vpref_min=minval(model_ref(j:nptref,7)*(1-vp_max)) ! setting min/max vph velocities for writing later
    vpref_max=maxval(model_ref(j:nptref,7)*(1+vp_max))

    ! vpref_min=minval(model_ref(j:nptref,4)*vpvs*(1+vp_min/100.)*(1-width)) 
    ! vpref_max=maxval(model_ref(j:nptref,4)*vpvs*(1+vp_max/100.)*(1+width))
    
    ! Edit lines below to match periods of synethetic data to real data
    ! Add / remove overtones as necessary.
    if (testing) then !!!!!!!testing: create synthetic model
        write(*,*)'testing'
    
!########################################################################################################

        ! GET SYNTH SWD DATA ---------------------------------------------------------------- 
        nlims_cur=1
        open(65,file='./Durand_data_raw.in',status='old')! 65: name of the opened file in memory (unit identifier)
        read(65,*,IOSTAT=io)ndatad_R ! number of Rayleigh modes
        read(65,*,IOSTAT=io)nharm_R ! number of harmonics

        do k=1,nharm_R
            read(65,*,IOSTAT=io)numharm_R(k) ! number of the harmonic (fundamental=0, first=1 etc.)
            read(65,*,IOSTAT=io)nlims_cur_diff ! number of modes for this harmonic
            nlims_R(1,k)=nlims_cur
            nlims_R(2,k)=nlims_R(1,k)+nlims_cur_diff
            do i=nlims_cur,nlims_cur+nlims_cur_diff
                read(65,*,IOSTAT=io)n_R(i),peri_R(i),dummy_d_obsdcR(i),d_obsdcRe(i)
                d_obsdcRe(i)=obs_err_R ! Manually override errors
            enddo
            nlims_cur=nlims_R(2,k)+1
        enddo
                
        nlims_cur=1
        read(65,*,IOSTAT=io)ndatad_L ! number of Love modes
        read(65,*,IOSTAT=io)nharm_L ! number of harmonics
        do k=1,nharm_L
            read(65,*,IOSTAT=io)numharm_L(k) ! number of the harmonic (fundamental=0, first=1 etc.)
            read(65,*,IOSTAT=io)nlims_cur_diff ! number of modes for this harmonic

            nlims_L(1,k)=nlims_cur
            nlims_L(2,k)=nlims_L(1,k)+nlims_cur_diff
            do i=nlims_cur,nlims_cur+nlims_cur_diff
                read(65,*,IOSTAT=io)n_L(i),peri_L(i),dummy_d_obsdcL(i),d_obsdcLe(i)
                d_obsdcLe(i)=obs_err_L ! Manually override errors
            enddo
            nlims_cur=nlims_L(2,k)+1
        enddo
        close(65)
        
        do k=1,nharm_R
            wmin_R(k)=1000./(maxval(peri_R(nlims_R(1,k):nlims_R(2,k)))+20)
            wmax_R(k)=1000./(minval(peri_R(nlims_R(1,k):nlims_R(2,k)))-2)
        enddo
        
        do k=1,nharm_L
            wmin_L(k)=1000./(maxval(peri_L(nlims_L(1,k):nlims_L(2,k)))+20)
            wmax_L(k)=1000./(minval(peri_L(nlims_L(1,k):nlims_L(2,k)))-2)
        enddo
        
        nmin_R=minval(n_R(:ndatad_R))
        nmax_R=maxval(n_R(:ndatad_R))
        
        nmin_L=minval(n_L(:ndatad_L))
        nmax_L=maxval(n_L(:ndatad_L))
        
        if (ndatad_R>=ndatad_L) tref=sum(peri_R(:ndatad_R))/ndatad_R
        if (ndatad_L>ndatad_R) tref=sum(peri_L(:ndatad_L))/ndatad_L

        !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
        if (PsPp_flag==1) then
            call get_rayp(rp_file, nrays, rayp)
            do i = 1, nrays
                d_obsPsPpe(i) = obs_err_PsPp
            end do
        end if
            
        !!!!!!!!!!!!!!!!!!!!!!!! create synthetic model !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        npt=0
        
        voro(npt+1,1)=0 !depth of interface
        voro(npt+1,2)=0.0  !vsv=vsv_prem*(1+voro(i,2))
        voro(npt+1,3)=-1   !0.7+0.5/33.*i !xi=voro(i,3), -1 for isotropic layer
        voro(npt+1,4)=0.0  !vph=vph_prem*(1+voro(i,4))
        npt=npt+1

        voro(npt+1,1)=100.0 !depth of interface
        voro(npt+1,2)=0.0  !vsv=vsv_prem*(1+voro(i,2))
        voro(npt+1,3)=-1   !0.7+0.5/33.*i !xi=voro(i,3), -1 for isotropic layer
        voro(npt+1,4)=0.05  !vph=vph_prem*(1+voro(i,4))
        npt=npt+1
        
        voro(npt+1,1)=200.0 !depth of interface
        voro(npt+1,2)=0.0  !vsv=vsv_prem*(1+voro(i,2))
        voro(npt+1,3)=-1   !0.7+0.5/33.*i !xi=voro(i,3), -1 for isotropic layer
        voro(npt+1,4)=0.0  !vph=vph_prem*(1+voro(i,4))
        npt=npt+1
        
        ! take voro, combine_linear_vp it with prem into a format suitable for minos
        call combine_linear_vp(model_ref,nptref,nic_ref,noc_ref,voro,npt,d_max,&
            r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,nptfinal,nic,noc,vs_data,xi,vp_data)
        
        !calculate synthetic dispersion curves
        if (ndatad_R>0) then
            jcom=3 !rayleigh waves
            
            do iharm=1,nharm_R
                nmodes=0
                call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                    qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                    wmin_R(iharm),wmax_R(iharm),numharm_R(iharm),numharm_R(iharm),&
                    nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                if (error_flag) stop "INVALID INITIAL MODEL - RAYLEIGH - minos_bran.f FAIL 001"
                peri_R_tmp=peri_R(nlims_R(1,iharm):nlims_R(2,iharm))
                ndatad_R_tmp=nlims_R(2,iharm)-nlims_R(1,iharm)+1 ! fortran slices take the first and the last element
                n_R_tmp(:ndatad_R_tmp)=n_R(nlims_R(1,iharm):nlims_R(2,iharm))
                
                call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                    peri_R_tmp,n_R_tmp,d_cR_tmp,rq_R,ndatad_R_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                d_cR(nlims_R(1,iharm):nlims_R(2,iharm))=d_cR_tmp
                if (ier) stop "INVALID INITIAL MODEL - RAYLEIGH - CHANGE PERIODS or MODEL"
                if (maxval(abs(rq_R(:ndatad_R_tmp)))>maxrq*eps) stop "INVALID INITIAL MODEL - RAYLEIGH - CHANGE PERIODS or MODEL"
            enddo
        endif
        
        if (ndatad_L>0) then
            jcom=2 !love waves
            do iharm=1,nharm_L
                nmodes=0
                call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                    qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                    wmin_L(iharm),wmax_L(iharm),numharm_L(iharm),numharm_L(iharm),&
                    nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                if (error_flag) stop "INVALID INITIAL MODEL - LOVE - minos_bran.f FAIL 002"
                peri_L_tmp=peri_L(nlims_L(1,iharm):nlims_L(2,iharm))
                ndatad_L_tmp=nlims_L(2,iharm)-nlims_L(1,iharm)+1 ! fortran slices take the first and the last element
                n_L_tmp(:ndatad_L_tmp)=n_L(nlims_L(1,iharm):nlims_L(2,iharm))
                
                call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                    peri_L_tmp,n_L_tmp,d_cL_tmp,rq_L,ndatad_L_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                d_cL(nlims_L(1,iharm):nlims_L(2,iharm))=d_cL_tmp
                if (ier) stop "INVALID INITIAL MODEL - LOVE - CHANGE PERIODS or MODEL"
                if (maxval(abs(rq_L(:ndatad_L_tmp)))>maxrq*eps) stop "INVALID INITIAL MODEL - LOVE - CHANGE PERIODS or MODEL"
            enddo
        endif

        d_obsdcR(:ndatad_R)=d_cR(:ndatad_R)
        d_obsdcL(:ndatad_L)=d_cL(:ndatad_L)

        !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
        if (PsPp_flag==1) then
            if (nrays>0) then
                call sum_Ps_Pp_diff(r, vpv, vph, vsv, vsh, nptfinal, nrays, rayp, d_obsPsPp, PsPp_error)
                if (PsPp_error) stop "INVALID INITIAL MODEL - PsPp - Gradient or Nan likely"
                ! do i = 1, nrays
                !     write(*,*) d_obsPsPp(i)
                ! end do
            end if
        end if

        ! Add Gaussian errors to synthetic data
        
        IF (nbproc.gt.1) THEN
            IF (ran==0) THEN
                do i=1,ndatad_R
                    d_obsdcR(i)=d_obsdcR(i)+gasdev(ra)*noise_dspd
                end do
                do i=1,ndatad_L
                    d_obsdcL(i)=d_obsdcL(i)+gasdev(ra)*noise_dspd*2 ! Make the Love noise twice the Rayleigh
                end do

                if (PsPp_flag==1) then
                    do i=1,nrays
                        d_obsPsPp(i)=d_obsPsPp(i)+gasdev(ra)*noise_PsPp
                    end do
                end if


                do i=2,nbproc
                    call MPI_SEND(d_obsdcR, ndatadmax, MPI_Real, i-1, 1, MPI_COMM_WORLD, ierror)
                    call MPI_SEND(d_obsdcL, ndatadmax, MPI_Real, i-1, 1, MPI_COMM_WORLD, ierror)

                    if (PsPp_flag==1) then
                        call MPI_SEND(d_obsPsPp, nrays_max, MPI_Real, i-1, 1, MPI_COMM_WORLD, ierror)
                    end if

                enddo
            else
                call MPI_RECV(d_obsdcR, ndatadmax, MPI_Real, 0, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierror)
                call MPI_RECV(d_obsdcL, ndatadmax, MPI_Real, 0, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierror)

                if (PsPp_flag==1) then
                    call MPI_RECV(d_obsPsPp, nrays_max, MPI_Real, 0, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierror)
                end if

            endif
        else
            do i=1,ndatad_R
                d_obsdcR(i)=d_obsdcR(i)+gasdev(ra)*noise_dspd
            end do
            do i=1,ndatad_L
                d_obsdcL(i)=d_obsdcL(i)+gasdev(ra)*noise_dspd*2 ! Make the Love noise twice the Rayleigh
            end do

            if (PsPp_flag==1) then
                do i=1,nrays
                    d_obsPsPp(i)=d_obsPsPp(i)+gasdev(ra)*noise_PsPp
                end do
            end if

        endif

        
        ! write synthetic model into a file
        open(64,file=dirname//'/true_voro_model.out',status='replace')
        do i=1,npt
            write(64,*)voro(i,1),voro(i,2),voro(i,3),voro(i,4)
        enddo
        close(64)

        open(65,file=dirname//'/true_model.out',status='replace')
        do i=1,nptfinal
            write(65,*)(rearth-r(i))/1000,vsv(i),xi(i),vph(i)
        enddo
        close(65)
        write(*,*)'DONE INITIALIZING SYNTHETIC MODEL'
    
    else ! real data , untested , unedited, will probably need a little work to get working
        ! GET SWD DATA ----------------------------------------------------------------
        write(*,*) 'Starting reading data....'
        nlims_cur=1
        open(65,file=dirname//'/mod_dispersion.in',status='old')! 65: name of the opened file in memory (unit identifier)
        read(65,*,IOSTAT=io)ndatad_R ! number of Rayleigh modes
        read(65,*,IOSTAT=io)nharm_R ! number of harmonics
        do k=1,nharm_R
            read(65,*,IOSTAT=io)numharm_R(k) ! number of the harmonic (fundamental=0, first=1 etc.)
            read(65,*,IOSTAT=io)nlims_cur_diff ! number of modes for this harmonic
            nlims_R(1,k)=nlims_cur
            nlims_R(2,k)=nlims_R(1,k)+nlims_cur_diff
            !read(65,*,IOSTAT=io)wmin_R(k),wmax_R(k)
            do i=nlims_cur,nlims_cur+nlims_cur_diff
                read(65,*,IOSTAT=io)n_R(i),peri_R(i),d_obsdcR(i),d_obsdcRe(i)
            enddo
            nlims_cur=nlims_R(2,k)+1
        enddo
        
        nlims_cur=1
        read(65,*,IOSTAT=io)ndatad_L ! number of Love modes
        read(65,*,IOSTAT=io)nharm_L ! number of harmonics
        do k=1,nharm_L
            read(65,*,IOSTAT=io)numharm_L(k) ! number of the harmonic (fundamental=0, first=1 etc.)
            read(65,*,IOSTAT=io)nlims_cur_diff ! number of modes for this harmonic
            nlims_L(1,k)=nlims_cur
            nlims_L(2,k)=nlims_L(1,k)+nlims_cur_diff
            !read(65,*,IOSTAT=io)wmin_L(k),wmax_L(k)
            do i=nlims_cur,nlims_cur+nlims_cur_diff
                read(65,*,IOSTAT=io)n_L(i),peri_L(i),d_obsdcL(i),d_obsdcLe(i)
            enddo
            nlims_cur=nlims_L(2,k)+1
        enddo
        close(65)
        
        do k=1,nharm_R
            wmin_R(k)=1000./(maxval(peri_R(nlims_R(1,k):nlims_R(2,k)))+20)
            wmax_R(k)=1000./(minval(peri_R(nlims_R(1,k):nlims_R(2,k)))-2)
        enddo
        
        do k=1,nharm_L
            wmin_L(k)=1000./(maxval(peri_L(nlims_L(1,k):nlims_L(2,k)))+20)
            wmax_L(k)=1000./(minval(peri_L(nlims_L(1,k):nlims_L(2,k)))-2)
        enddo
        
        nmin_R=minval(n_R(:ndatad_R))
        nmax_R=maxval(n_R(:ndatad_R))
        
        nmin_L=minval(n_L(:ndatad_L))
        nmax_L=maxval(n_L(:ndatad_L))
        
        if (ndatad_R>=ndatad_L) tref=sum(peri_R(:ndatad_R))/ndatad_R
        if (ndatad_L>ndatad_R) tref=sum(peri_L(:ndatad_L))/ndatad_L
        

        ! ############# READ PsPp data here #######################
        if (PsPp_flag==1) then
            open(71,file=dirname//'/PsPp_obs.dat',status='old')
            read(71,*,IOSTAT=io)nrays
            do i=1,nrays
                read(71,*)rayp(i),d_obsPsPp(i),d_obsPsPpe(i)
                if ((rayp(i).gt.8.840).or.(rayp(i).lt.4.642)) then
                    stop "INVALID rayp data in PsPp_obs.dat. Exiting......."
                end if
            enddo
            close(71)
        end if
        write(*,*) 'Finished reading data....'

    endif
    
    !ra=rank
    !***************************************************
    !***************************************************
    !**************************************************************

    !    Draw the first model randomly from the prior distribution

    !**************************************************************
    
    ! Initilalise sigma (noise parameter)
    Ad_R = sp_Ad_R_max-pAd_R! Ad_min+ran3(ra)*(Ad_R_max-Ad_min)
    Ad_L = sp_Ad_L_max-pAd_L
    if (PsPp_flag==1) then
        Ad_PsPp = sp_Ad_PsPp_max-pAd_PsPp
    end if

    ! Initial number of cells
    !------------------------------------

    j=0
    tes=.false.
    do while(.not.tes)
50      tes=.true.
        ! create a starting model randomly
        npt = milay+ran3(ra)*(sp_malay-milay)
        if ((npt>malay).or.(npt<milay)) goto 50
        write(*,*)npt
        j=j+1


        ! first layer always at 0
        voro(1,1)= 0.
        voro(1,2)= (-sp_width+2*sp_width*ran3(ra))
        if (ran3(ra)<0.5) then
            voro(1,3)= sp_xi_min+(sp_xi_max-sp_xi_min)*ran3(ra)
        else
            voro(1,3)= -1
        endif
        if (vp_flag==0) then
            ! Vp Free
            voro(1,4) = sp_vp_min+(sp_vp_max-sp_vp_min)*ran3(ra)
        elseif (vp_flag==1) then
            ! Vp scaled
            if (vp_scale.gt.1.0) then
                voro(1,4) = voro(1,2) * vp_scale_S40(voro(1,1))
            else
                voro(1,4) = voro(1,2) * vp_scale
            endif
        elseif (vp_flag==2) then
            ! Vp Fixed to ref
            voro(1,4) = 0.0
        end if

        do i=2,npt

            voro(i,1)= d_min+ran3(ra)*(d_max-d_min) ! Scatters depth points between min and max value
            voro(i,2)= (-sp_width+2*sp_width*ran3(ra))
            if (ran3(ra)<0.5) then
                voro(i,3)= sp_xi_min+(sp_xi_max-sp_xi_min)*ran3(ra)
            else
                voro(i,3)= -1
            endif

            if (vp_flag==0) then
                ! Vp Free
                voro(i,4) = sp_vp_min+(sp_vp_max-sp_vp_min)*ran3(ra)
            elseif (vp_flag==1) then
                ! Vp scaled
                if (vp_scale.gt.1.0) then
                    voro(i,4) = voro(i,2) * vp_scale_S40(voro(i,1))
                else
                    voro(i,4) = voro(i,2) * vp_scale
                endif
            elseif (vp_flag==2) then
                ! Vp Fixed to ref
                voro(i,4) = 0.0
            end if
           
        enddo

        ! ! Should not be necessary here.....
        ! do i=1,npt
        !     do k=1,npt-1 
        !         if (voro(k,1).gt.voro(k+1,1)) then
        !             t = voro(k,:);  voro(k,:) = voro(k+1,:);  voro(k+1,:) = t
        !         ENDIF
        !     ENDDO
        ! ENDDO

!         open(65,file=dirname//'/stuck_039.out',status='old')
!         read(65,*,IOSTAT=io)npt
!         do i=1,npt
!             read(65,*,IOSTAT=io)voro(i,1),voro(i,2),voro(i,3),voro(i,4)
!         enddo
!         close(65)

        call combine_linear_vp(model_ref,nptref,nic_ref,noc_ref,voro,npt,d_max,&
            r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,nptfinal,nic,noc,vs_data,xi,vp_data)
        write(*,*)"Combined"
        if (ndatad_R>0) then
            
            jcom=3 !rayleigh waves
            
            do iharm=1,nharm_R
                nmodes=0
                call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                    qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                    wmin_R(iharm),wmax_R(iharm),numharm_R(iharm),numharm_R(iharm),&
                    nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                if (error_flag) then 
                    tes=.false.
                    write(*,*)"Minos_bran FAILED for RAYLEIGH 004"
                else
                    write(*,*)"Minos_bran SUCCESS for RAYLEIGH"
                end if
                peri_R_tmp=peri_R(nlims_R(1,iharm):nlims_R(2,iharm))
                n_R_tmp=n_R(nlims_R(1,iharm):nlims_R(2,iharm))
                ndatad_R_tmp=nlims_R(2,iharm)-nlims_R(1,iharm)+1 ! fortran slices take the first and the last element
                call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                    peri_R_tmp,n_R_tmp,d_cR_tmp,rq_R,ndatad_R_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                write(*,*)"dispersion_minos for RAYLEIGH"
                d_cR(nlims_R(1,iharm):nlims_R(2,iharm))=d_cR_tmp
                if (ier) tes=.false.
                if (maxval(abs(rq_R(:ndatad_R_tmp)))>maxrq*eps) tes=.false.
            enddo
        endif
        
        if (ndatad_L>0) then
        
            jcom=2 !love waves
            do iharm=1,nharm_L
                nmodes=0
                call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                    qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                    wmin_L(iharm),wmax_L(iharm),numharm_L(iharm),numharm_L(iharm),&
                    nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                if (error_flag) then 
                    tes=.false.
                    write(*,*)"Minos_bran FAILED for LOVE 004"
                else
                    write(*,*)"Minos_bran SUCCESS for LOVE"
                end if
                peri_L_tmp=peri_L(nlims_L(1,iharm):nlims_L(2,iharm))
                n_L_tmp=n_L(nlims_L(1,iharm):nlims_L(2,iharm))
                ndatad_L_tmp=nlims_L(2,iharm)-nlims_L(1,iharm)+1 ! fortran slices take the first and the last element
                call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                peri_L_tmp,n_L_tmp,d_cL_tmp,rq_L,ndatad_L_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                write(*,*)"dispersion_minos for LOVE"
                d_cL(nlims_L(1,iharm):nlims_L(2,iharm))=d_cL_tmp
                if (ier) tes=.false.
                if (maxval(abs(rq_L(:ndatad_L_tmp)))>maxrq*eps) tes=.false.
            enddo
        
        endif
        
        if (PsPp_flag==1) then
            !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
            if (nrays>0) then
                call sum_Ps_Pp_diff(r, vpv, vph, vsv, vsh, nptfinal, nrays, rayp, d_PsPp, PsPp_error)
    !             if (PsPp_error) tes=.false.
                if (PsPp_error) then
                    tes=.false.
                    write(*,*)"INVALID PROPOSED MODEL - PsPp - Gradient or Nan likely"
                end if
            end if
        end if

        if (j>250) stop "CAN'T INITIALIZE MODEL" ! if it doesn't work after 250 tries, give up

    enddo

    write(*,*)'DONE INITIALIZING STARTING MODEL'
    
    ! isoflag says if a layer is isotropic
    do i=1,npt
        if (voro(i,3)==-1) then
            isoflag(i)=.true.
        else
            isoflag(i)=.false.
        endif
    enddo
    
    write(*,*)'getting initial likelihood'
    !***********************************************************

    !                 Get initial likelihood

    !***********************************************************

    lsd_R=0
    lsd_L=0
    liked_R=0
    liked_L=0

    if (PsPp_flag==1) then
        lsd_PsPp = 0
        liked_PsPp = 0
    end if
    
    do i=1,ndatad_R ! calculate misfit -> log-likelihood of initial model
        lsd_R=lsd_R+(d_obsdcR(i)-d_cR(i))**2                                ! Sum of squared misfits
        liked_R=liked_R+(d_obsdcR(i)-d_cR(i))**2/(2*(Ad_R*d_obsdcRe(i))**2) ! gaussian errors
    enddo
    do i=1,ndatad_L
        lsd_L=lsd_L+(d_obsdcL(i)-d_cL(i))**2
        liked_L=liked_L+(d_obsdcL(i)-d_cL(i))**2/(2*(Ad_L*d_obsdcLe(i))**2) 
    enddo

    if (PsPp_flag==1) then
        do i=1,nrays
            lsd_PsPp=lsd_PsPp+(d_obsPsPp(i)-d_PsPp(i))**2
            liked_PsPp=liked_PsPp+(d_obsPsPp(i)-d_PsPp(i))**2/(2*(Ad_PsPp*d_obsPsPpe(i))**2)
        enddo
    end if

    lsd_R_min=lsd_R
    lsd_L_min=lsd_L

    if (PsPp_flag==1) then
        lsd_PsPp_min=lsd_PsPp
        likemax=lsd_R+lsd_L+lsd_PsPp
        like= liked_R + liked_L + liked_PsPp  ! Combined log likelihood for R, L PsPp
    else
        likemax=lsd_R+lsd_L
        like= liked_R + liked_L             ! Combined log likelihood for R and L
    end if

    
    write(*,*)like
    
    stuck=.false.
    
    sample=0    ! Sampling counter (nsamples)
    th=0        ! Chain thinning counter
    ount=0      ! Total: burn-in+nsamples
    PrP=0
    PrV=0
    PrB=0
    PrD=0
    PrBa=0
    PrDa=0
    AcP=0
    AcV=0
    AcB=0
    AcD=0
    AcBa=0
    AcDa=0
    Acnd_R=0
    Prnd_R=0
    Prxi=0
    Acxi=0
    Pr_vp=0
    Ac_vp=0
    Prnd_L=0
    Acnd_L=0

    if (PsPp_flag==1) then
        Prnd_PsPp=0
        Acnd_PsPp=0
    end if

    sigmav_old=0
    sigmavp_old=0
    sigma_count=0
    
    Ar_birth_old=0   
    
    recalculated=0
    
    write(*,*)'all initialized' 

    write(filenamemax,"('/All_models_invert_',I3.3,'_',I3.3,'.out')") rank, sample/everyall
    open(100,file=mods_dirname//filenamemax,status='replace')
    write(100,*)rank,sample/everyall,everyall
    write(100,*)burn_in,nsample,thin
    write(100,*)d_min,d_max
    write(100,*)-width,width,vsref_min,vsref_max
    write(100,*)xi_min,xi_max
    write(100,*)vp_min,vp_max,vpref_min,vpref_max
    write(100,*)Ad_R_min,Ad_R_max
    write(100,*)Ad_L_min,Ad_L_max
    ! write(100,*)Ad_PsPp_min,Ad_PsPp_max ! Cant do this without changing post processing.

    do while (sample<nsample) ! main loop, sample: number of sample post burn-in
        ount=ount+1
        malayv=malay
        if (mod(ount,every)==0) then ! check regularly if acceptance rates are in an acceptable range, else change proposal width.
            if (vp_flag==0) then
                ! Vp Free
                if ((Ac_vp/(Pr_vp+1))>0.54) p_vp=p_vp*(1+perturb)! if not increase width of proposition density
                if ((Ac_vp/(Pr_vp+1))<0.34) p_vp=p_vp*(1-perturb)! or decrease it
            elseif (vp_flag==1) then
                ! Vp scaled
                p_vp=p_vp
            elseif (vp_flag==2) then
                ! Vp Fixed to ref
                p_vp=p_vp
            end if
            if ((Acxi/(Prxi+1))>0.54) pxi=pxi*(1+perturb)
            if ((Acxi/(Prxi+1))<0.34) pxi=pxi*(1-perturb)
            if ((Acnd_R/(Prnd_R+1))>0.54) pAd_R=pAd_R*(1+perturb) ! for rayleigh waves
            if ((Acnd_R/(Prnd_R+1))<0.34) pAd_R=pAd_R*(1-perturb)
            if ((Acnd_L/(Prnd_L+1))>0.54) pAd_L=pAd_L*(1+perturb) ! for love waves
            if ((Acnd_L/(Prnd_L+1))<0.34) pAd_L=pAd_L*(1-perturb)
            
            if (PsPp_flag==1) then
                if ((Acnd_PsPp/(Prnd_PsPp+1))>0.54) pAd_PsPp=pAd_PsPp*(1+perturb) ! for PsPp
                if ((Acnd_PsPp/(Prnd_PsPp+1))<0.34) pAd_PsPp=pAd_PsPp*(1-perturb)
            end if

            if ((Acv/(Prv+1))>0.54) pv1=pv1*(1+perturb) ! 2 layers for vsv
            if ((Acv/(Prv+1))<0.34) pv1=pv1*(1-perturb)
      
            ! if ((Acv(2)/(Prv(2)+1))>0.54) pv2=pv2*(1+perturb) 
            ! if ((Acv(2)/(Prv(2)+1))<0.34) pv2=pv2*(1-perturb)
      
            if ((Acp/(Prp+1))>0.54) pd1=pd1*(1+perturb) ! 2 layers for changing depth
            if ((Acp/(Prp+1))<0.34) pd1=pd1*(1-perturb)
       
            ! if ((Acp(2)/(Prp(2)+1))>0.54) pd2=pd2*(1+perturb)
            ! if ((Acp(2)/(Prp(2)+1))<0.34) pd2=pd2*(1-perturb)
            !------------------------------------------------
            ! UPDATE SIGMAV & SIGMAVP

            !write(*,*) '****',AcB/PrB,(Ar_birth_old/100.),0.5*((AcB/PrB)-(AcD/PrD))
            if ((abs((AcB/PrB)-Ar_birth_old)>2*abs((AcB/PrB)-(AcD/PrD))).and.&
                (AcB.ne.0)) then !special treatement for adding/removing layers
                !write(*,*)
                !write(*,*)'update ---------------------'
                !write(*,*)Ar_birth_old,100*AcB/PrB
                !write(*,*)sigmav_old,sigmav
                                
                sigma_count=sigma_count+1
                if (vp_flag==0) then
                    ! Vp Free
                    if ((AcB/PrB)>Ar_birth_old) then! Going in the right direction
                        if (mod(int(sigma_count/switch_sigma),2)==0) then
                            if (sigmav>sigmav_old) then !Going up
                                sigmav_new=sigmav*(1+perturb)
                            else !Going down
                                sigmav_new=sigmav*(1-perturb)
                            endif
                            ! sigmavp_new=sigmavp
                            sigmav_old=sigmav
                            sigmav=sigmav_new
                        else
                            ! sigmavp
                            if (sigmavp>sigmavp_old) then !Going up
                                sigmavp_new=sigmavp*(1+perturb)
                            else !Going down
                                sigmavp_new=sigmavp*(1-perturb)
                            endif
                            ! sigmav_new=sigmav
                            sigmavp_old=sigmavp
                            sigmavp=sigmavp_new
                        endif
                    else ! Going in the wrong direction
                        if (mod(int(sigma_count/switch_sigma),2)==0) then
                            if (sigmav>sigmav_old) then !Going up
                                sigmav_new=sigmav*(1-perturb)
                            else
                                sigmav_new=sigmav*(1+perturb)
                            endif
                            ! sigmavp_new=sigmavp
                            sigmav_old=sigmav
                            sigmav=sigmav_new
                        else
                            ! sigmavp
                            if (sigmavp>sigmavp_old) then !Going up
                                sigmavp_new=sigmavp*(1-perturb)
                            else
                                sigmavp_new=sigmavp*(1+perturb)
                            endif
                            ! sigmav_new=sigmav
                            sigmavp_old=sigmavp
                            sigmavp=sigmavp_new
                        endif
                    endif
                else
                    if ((AcB/PrB)>Ar_birth_old) then! Going in the right direction
                        if (sigmav>sigmav_old) then !Going up
                            sigmav_new=sigmav*(1+perturb)
                        else !Going down
                            sigmav_new=sigmav*(1-perturb)
                        endif
                    else ! Going in the wrong direction
                        if (sigmav>sigmav_old) then !Going up
                            sigmav_new=sigmav*(1-perturb)
                        else
                            sigmav_new=sigmav*(1+perturb)
                        endif
                    endif
                    sigmavp_new=sigmavp
                endif

                !write(*,*)sigmav_new
                !write(*,*)
                ! sigmav_old=sigmav
                ! sigmav=sigmav_new

                ! sigmavp_old=sigmavp
                ! sigmavp=sigmavp_new

                Ar_birth_old=AcB/PrB
                PrB=0
                PrD=0
                AcB=0
                AcD=0
            endif
            
            if (vp_flag==0) then
                ! Vp Free
                if ((Ac_vp/(Pr_vp+1))<0.01) then 
                    write(filenamemax,"('/stuck_',I3.3,'.out')") rank    
                    open(56,file=dirname//filenamemax,status='replace')
                    write(56,*) npt
                    do i=1,npt
                        write(56,*)voro(i,1),voro(i,2),voro(i,3),voro(i,4)
                    enddo
                    close(56)
                    stuck=.true.
                endif
            end if

            !-----------------------------------------------

            PrP=0
            PrV=0
            PrBa=0
            PrDa=0
            AcP=0
            AcV=0
            AcBa=0
            AcDa=0
            Acnd_R=0
            Prnd_R=0
            Acxi=0
            Prxi=0
            Ac_vp=0
            Pr_vp=0
            Prnd_L=0
            Acnd_L=0

            if (PsPp_flag==1) then
                Prnd_PsPp=0
                Acnd_PsPp=0
            end if

        endif
    
        isoflag_prop = isoflag
        voro_prop=voro
        like_prop =like
        liked_R_prop=liked_R
        liked_L_prop=liked_L
        npt_prop = npt
        lsd_R_prop = lsd_R
        lsd_L_prop = lsd_L
        Ad_R_prop = Ad_R
        Ad_L_prop = Ad_L

        if (PsPp_flag==1) then
            liked_PsPp_prop=liked_PsPp
            lsd_PsPp_prop =lsd_PsPp
            Ad_PsPp_prop = Ad_PsPp
        end if

        ! Determine the random value used in proposals - need to change to account for Vp and PsPp.
        if (PsPp_flag==1) then
            if (vp_flag==0) then
                ! Vp Free
                u=ran3(ra) * 1.1
                if (u.ge.1.1) then
                    u=1.05
                endif
            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Vp scaled or Fixed to ref
                u=ran3(ra) * 1.0 ! We don't make a Vp change proposal in this case.
                if (u.ge.1.0) then
                    u=0.95
                endif
            end if
        elseif (PsPp_flag==0) then
            if (vp_flag==0) then
                ! Vp Free
                u=0.1+(ran3(ra) * 1.0)
                if (u.lt.0.1) then
                    u=0.15
                endif
                if (u.ge.1.1) then
                    u=1.05
                endif
            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Vp scaled or Fixed to ref
                u=0.1+(ran3(ra) * 0.9) ! We don't make a Vp change proposal in this case.
                if (u.lt.0.1) then
                    u=0.15
                endif
                if (u.ge.1.0) then
                    u=0.95
                endif
            end if
        end if

        ind=1
        out=1 ! indicates if change is acceptable, i. e. not out of bounds etc.
        move=.false.
        value=.false.
        birth=.false.
        birtha=.false.
        deatha=.false.
        death=.false.
        noisd_R=.false.
        noisd_L=.false.
        logprob_vsv=0
        logprob_vp=0
        ani=.false.
        change_vp=.false.

        if (PsPp_flag==1) then
            noisd_PsPp=.false.
        end if

        npt_ani=0
        npt_iso=0
        
        do i=1,npt
            if (isoflag(i).eqv..true.) npt_iso=npt_iso+1
            if (isoflag(i).eqv..false.) npt_ani=npt_ani+1
        enddo
        if ((npt_iso+npt_ani).ne.npt) stop "Error here"

        !*************************************************************

        !                   Propose a new model

        !*************************************************************

        if (u<0.1) then ! Change noise parameter for PsPp waves
            noisd_PsPp=.true.
            Prnd_PsPp = Prnd_PsPp + 1
            Ad_PsPp_prop = Ad_PsPp+gasdev(ra)*pAd_PsPp
            !Check if oustide bounds of prior
            if ((Ad_PsPp_prop<=Ad_PsPp_min).or.(Ad_PsPp_prop>=Ad_PsPp_max)) then
                out=0
            endif
            
            if (PsPp_flag==0) then
                ! Code should not get here....
                ! Write some exit statement....
                stop "Incorrect place for noisd_PsPp proposal change when PsPp_flag==0"
            end if

        elseif (u<0.2) then !change xi--------------------------------------------
            Prxi=Prxi+1 !increase counter to calculate acceptance rates
            ani=.true.
            if (npt_ani.ne.0) then
                ! Choose randomly an anisotropic cell among the npt_ani possibilities
                ind2 = ceiling(ran3(ra)*(npt_ani))
                if (ind2==0) ind2=1 !number of the anisotropic cell
                    
                j=0
                do ii=1,npt
                    if (isoflag(ii).eqv..false.) j=j+1
                    if (j==ind2) then
                        ind=ii ! number of the cell in voro
                        exit
                    endif
                enddo
                
                if (ind>npt) stop "684"
                if (voro(ind,3)==-1) stop "874" ! Anisotropic layer selected is isotropic...
                voro_prop(ind,3)=voro(ind,3)+gasdev(ra)*pxi
                if (isoflag(ind).eqv..true.) stop "isoflag1"
                
                ! Check prior on velocity when moving cell location - this is not necessary so comment...
                if ((voro_prop(ind,2)<=-width).or.(voro_prop(ind,2)>=width)) then
                    out=0
                endif
                !Check if oustide bounds of prior
                if ((voro_prop(ind,3)<=xi_min).or.(voro_prop(ind,3)>=xi_max)) then
                    out=0
                endif
                !Check if scaled vph oustide bounds of prior - should not happen.
                if ((voro_prop(ind,4)<=vp_min).or.(voro_prop(ind,4)>=vp_max)) then
                    out=0
                endif

            else
                out=0
            endif

        elseif (u<0.3) then !change position--------------------------------------------
            move=.true.

            ind=1+ceiling(ran3(ra)*(npt-1))
            if (ind==1) ind=2
            PrP=PrP+1
            voro_prop(ind,1)=voro(ind,1)+gasdev(ra)*pd1
 
            if ((voro_prop(ind,1)<=d_min).or.(voro_prop(ind,1)>=d_max)) then
                out=0
            endif
            ! Check prior on velocity when moving cell location - this is not necessary so comment...
            if ((voro_prop(ind,2)<=-width).or.(voro_prop(ind,2)>=width)) then
                out=0
            endif
            !Check if scaled vph oustide bounds of prior - should not happen.
            if ((voro_prop(ind,4)<=vp_min).or.(voro_prop(ind,4)>=vp_max)) then
                out=0
            endif

        elseif (u<0.4) then ! Change noise parameter for rayleigh waves
            noisd_R=.true.
            Prnd_R = Prnd_R + 1
            Ad_R_prop = Ad_R+gasdev(ra)*pAd_R
            !Check if oustide bounds of prior
            if ((Ad_R_prop<=Ad_R_min).or.(Ad_R_prop>=Ad_R_max)) then
                out=0
            endif
        elseif (u<0.5) then ! Change noise parameter for love waves
            noisd_L=.true.
            Prnd_L = Prnd_L + 1
            Ad_L_prop = Ad_L+gasdev(ra)*pAd_L
            !Check if oustide bounds of prior
            if ((Ad_L_prop<=Ad_L_min).or.(Ad_L_prop>=Ad_L_max)) then
                out=0
            endif

        elseif (u<0.6) then ! change vsv-----------------------------------
            
            value=.true.
            ind=ceiling(ran3(ra)*npt)
            if (ind==0) ind=1

            if (ind>npt) then
                write(*,*)npt,ind
                stop "763"
            endif
            
            PrV=PrV+1
            voro_prop(ind,2)=voro(ind,2)+gasdev(ra)*pv1
            
            if (vp_flag==0) then
                ! Vp Free
                voro_prop(ind,4) = voro_prop(ind,4)
            elseif (vp_flag==1) then
                ! Vp scaled
                if (vp_scale.gt.1.0) then
                    voro_prop(ind,4) = voro_prop(ind,2) * vp_scale_S40(voro_prop(ind,1))
                else
                    voro_prop(ind,4) = voro_prop(ind,2) * vp_scale
                endif

            elseif (vp_flag==2) then
                ! Vp Fixed to ref
                voro_prop(ind,4) = 0.0
            end if

            ! Check prior on velocity 
            if ((voro_prop(ind,2)<=-width).or.(voro_prop(ind,2)>=width)) then
                out=0
            endif
            !Check if scaled vph oustide bounds of prior - should not happen.
            if ((voro_prop(ind,4)<=vp_min).or.(voro_prop(ind,4)>=vp_max)) then
                out=0
            endif

        elseif (u<0.7) then !Birth of an isotropic cell -------------------------------------
            birth = .true.
            PrB = PrB + 1
            npt_prop = npt + 1
            if (npt_prop>malayv) then  !MODIF 
                out=0
            else
                voro_prop(npt_prop,1) = d_min+ran3(ra)*(d_max-d_min)
                call whichcell_d(voro_prop(npt_prop,1),voro,npt,ind)!

                voro_prop(npt_prop,2) = voro(ind,2)+gasdev(ra)*sigmav ! sigmav: special width for new layers
                voro_prop(npt_prop,3) = -1
                isoflag_prop(npt_prop) = .true. 
                logprob_vsv=log(1/(sigmav*sqrt(2*pi)))-((voro(ind,2)-voro_prop(npt_prop,2))**2)/(2*sigmav**2) ! correct acceptance rates because transdimensional
                                
                if (vp_flag==0) then
                    ! Vp Free
                    voro_prop(npt_prop,4) = voro(ind,4)+gasdev(ra)*sigmavp ! sigmavp: special width for new layers
                    logprob_vp=log(1/(sigmavp*sqrt(2*pi)))-((voro(ind,4)-voro_prop(npt_prop,4))**2)/(2*sigmavp**2)
                elseif (vp_flag==1) then
                    ! Vp scaled
                    if (vp_scale.gt.1.0) then
                        voro_prop(npt_prop,4) = voro_prop(npt_prop,2) * vp_scale_S40(voro_prop(npt_prop,1))
                    else
                        voro_prop(npt_prop,4) = voro_prop(npt_prop,2) * vp_scale
                    endif
                    logprob_vp = 1.0
                elseif (vp_flag==2) then
                    ! Vp Fixed to ref
                    voro_prop(npt_prop,4) = 0.0
                    logprob_vp = 1.0
                end if

                !Check bounds                    
                if ((voro_prop(npt_prop,2)<=-width).or.(voro_prop(npt_prop,2)>=width)) then
                    out=0
                end if
                if ((voro_prop(npt_prop,4)<=vp_min).or.(voro_prop(npt_prop,4)>=vp_max)) then
                    out=0
                end if




            endif
        elseif (u<0.8) then !death of an isotropic cell !---------------------------------------    !

            death = .true.
            PrD = PrD + 1
            if(npt_iso==0) then
                out=0
            else
            
                ind2 = ceiling(ran3(ra)*(npt_iso)) 
                if (ind2==0) ind2=1

                j=0
                do ii=1,npt
                    if (isoflag(ii).eqv..true.) j=j+1
                    if (j==ind2) then
                        ind=ii
                        exit
                    endif
                enddo
                if (voro(ind,3).NE.-1) stop "1092" 
            endif

            npt_prop=npt-1
            
            if ((npt_prop<milay).or.(ind==1)) then ! don't remove the first layer
                out=0
            else
                voro_prop(ind,:)=voro(npt,:)
                isoflag_prop(ind)=isoflag(npt)
            
                call whichcell_d(voro(ind,1),voro_prop,npt_prop,ind2)
                logprob_vsv= log(1/(sigmav*sqrt(2*pi)))-((voro(ind,2)-voro_prop(ind2,2))**2)/(2*sigmav**2) ! same as for birth
                
                if (vp_flag==0) then
                    ! Vp Free
                    logprob_vp=log(1/(sigmavp*sqrt(2*pi)))-((voro(ind,4)-voro_prop(ind2,4))**2)/(2*sigmavp**2)
                elseif ((vp_flag==1).or.(vp_flag==2)) then
                    ! Vp scaled or Vp Fixed to ref
                    logprob_vp = 1.0 
                end if
                
            endif
        elseif (u<0.9) then !Birth of an anisotropic layer----------------------------------------
            birtha = .true.
            PrBa = PrBa + 1    
            if (npt_iso==0) then
                out=0
            else
                ! Choose randomly an isotropic cell among the npt_iso possibilities
                ind2 = ceiling(ran3(ra)*(npt_iso))
                if (ind2==0) ind2=1
                j=0
                do ii=1,npt
                    if (isoflag(ii).eqv..true.) j=j+1
                    if (j==ind2) then
                        ind=ii
                        exit
                    endif
                enddo
                voro_prop(ind,3) =  xi_min+(xi_max-xi_min)*ran3(ra) ! Seems quite wild to guess over this whole range.
                if (voro(ind,3).NE.-1) stop "1130"
                if ((voro_prop(ind,3)<=xi_min).or.(voro_prop(ind,3)>=xi_max)) then
                    ! write(*,*)'anisotropy out of bounds'
                    out=0
                endif
                isoflag_prop(ind)=.false.
            endif
        elseif (u<1.0) then !death of an anisotropic layer!---------------------------------------    
            deatha = .true.
            PrDa = PrDa + 1
            if (npt_ani==0) then
                out=0
            else
                ! Choose randomly an anisotropic cell among the npt_ani possibilities
                ind2 = ceiling(ran3(ra)*(npt_ani))
                if (ind2==0) ind2=1
                j=0
                do ii=1,npt
                    if (isoflag(ii).eqv..false.) j=j+1
                    if (j==ind2) then
                        ind=ii
                        exit
                    endif
                enddo
                voro_prop(ind,3)=-1
                isoflag_prop(ind)=.true.
            endif
        
        ! Will never be above 1.1 so can use 1.2 below.
        elseif (u<1.2) then !change vp --------------------------------------------
            if (vp_flag==0) then
                ! Vp Free
                change_vp=.true.
                
                ! Choose a random cell
                ind=ceiling(ran3(ra)*npt)
                if (ind==0) ind=1
                
                Pr_vp=Pr_vp+1
                if (ind>npt) then
                    out=0
                else
                    voro_prop(ind,4)=voro(ind,4)+gasdev(ra)*p_vp
    
                    !Check if oustide bounds of prior
                    if ((voro_prop(ind,4)<=vp_min).or.(voro_prop(ind,4)>=vp_max)) then
                        out=0
                    endif
                    if ((voro_prop(ind,2)<=-width).or.(voro_prop(ind,2)>=width)) then
                        out=0
                    end if
                endif

            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Code should not get here....
                ! Write some exit statement....
                stop "Incorrect place for vph proposal change..."
            end if
        else
            out=0
        endif
        
        !**************************************************************************

        !         After  moving a cell, Get the misfit of the proposed model

        !**************************************************************************
        if (out==1) then
            call combine_linear_vp(model_ref,nptref,nic_ref,noc_ref,voro_prop,npt_prop,d_max,&
                r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,nptfinal,nic,noc,vs_data,xi,vp_data)
            
            if (ndatad_R>0) then
                
                jcom=3 !rayleigh waves
                
                do iharm=1,nharm_R
                    nmodes=0
                    call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                        qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                        wmin_R(iharm),wmax_R(iharm),numharm_R(iharm),numharm_R(iharm),&
                        nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                    if (error_flag) then 
                        out=0
                        write(*,*)"INVALID PROPOSED MODEL - RAYLEIGH MODE: ",numharm_R(iharm)," - minos_bran.f FAIL 005"
                        goto 1142
                    endif
                    
                    peri_R_tmp=peri_R(nlims_R(1,iharm):nlims_R(2,iharm))
                    n_R_tmp=n_R(nlims_R(1,iharm):nlims_R(2,iharm))
                    ndatad_R_tmp=nlims_R(2,iharm)-nlims_R(1,iharm)+1 ! fortran slices take the first and the last element
                    call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                        peri_R_tmp,n_R_tmp,d_cR_prop_tmp,rq_R,ndatad_R_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                    !write(*,*)"dispersion_minos for RAYLEIGH"
                    d_cR_prop(nlims_R(1,iharm):nlims_R(2,iharm))=d_cR_prop_tmp
                    
                    if (ier) then 
                        out=0
                        write(*,*)"INVALID PROPOSED MODEL - RAYLEIGH MODE: ",numharm_R(iharm)
                        goto 1142
                    endif
                    
                    if (maxval(abs(rq_R(:ndatad_R_tmp)))>maxrq*eps) then
                        out=0
                        write(*,*)"BAD UNCERTAINTIES - RAYLEIGH MODE: ",numharm_R(iharm)
                        goto 1142
                    endif
                enddo
            endif
            
            if (ndatad_L>0) then
            
                jcom=2 !love waves
                do iharm=1,nharm_L
                    nmodes=0
                    call minos_bran(1,tref,nptfinal,nic,noc,r,rho,vpv,vph,vsv,vsh,&
                        qkappa,qshear,eta,eps,wgrav,jcom,lmin,lmax,&
                        wmin_L(iharm),wmax_L(iharm),numharm_L(iharm),numharm_L(iharm),&
                        nmodes_max,nmodes,n_mode,l_mode,c_ph,period,raylquo,error_flag) ! calculate normal modes
                    if (error_flag) then 
                        out=0
                        write(*,*)"INVALID PROPOSED MODEL - LOVE MODE: ",numharm_L(iharm)," - minos_bran.f FAIL 006"
                        goto 1142
                    endif
                    
                    peri_L_tmp=peri_L(nlims_L(1,iharm):nlims_L(2,iharm))
                    n_L_tmp=n_L(nlims_L(1,iharm):nlims_L(2,iharm))
                    ndatad_L_tmp=nlims_L(2,iharm)-nlims_L(1,iharm)+1 ! fortran slices take the first and the last element
                    call dispersion_minos(nmodes_max,nmodes,n_mode,c_ph,period,raylquo,&
                        peri_L_tmp,n_L_tmp,d_cL_prop_tmp,rq_L,ndatad_L_tmp,ier) ! extract phase velocities from minos output (pretty ugly)
                    !write(*,*)"dispersion_minos for LOVE"
                    d_cL_prop(nlims_L(1,iharm):nlims_L(2,iharm))=d_cL_prop_tmp
                    
                    if (ier) then 
                        out=0
                        write(*,*)"INVALID PROPOSED MODEL - LOVE MODE: ",numharm_L(iharm)
                        goto 1142
                    endif
                    
                    if (maxval(abs(rq_L(:ndatad_L_tmp)))>maxrq*eps) then
                        out=0
                        write(*,*)"BAD UNCERTAINTIES - LOVE MODE: ",numharm_L(iharm)
                        goto 1142
                    endif
                enddo
            endif
            
            lsd_R_prop=0
            lsd_L_prop=0
            liked_R_prop=0
            liked_L_prop=0
            do i=1,ndatad_R
                lsd_R_prop=lsd_R_prop+(d_obsdcR(i)-d_cR_prop(i))**2
                liked_R_prop=liked_R_prop+(d_obsdcR(i)-d_cR_prop(i))**2/(2*(Ad_R_prop*d_obsdcRe(i))**2) ! prendre en compte erreurs mesurées / include measurement errors
            end do
            do i=1,ndatad_L
                lsd_L_prop=lsd_L_prop+(d_obsdcL(i)-d_cL_prop(i))**2
                liked_L_prop=liked_L_prop+(d_obsdcL(i)-d_cL_prop(i))**2/(2*(Ad_L_prop*d_obsdcLe(i))**2) ! prendre en compte erreurs mesurées / include measurement errors
            end do


            if (PsPp_flag==1) then
                !!!!!!!!!!!!!!! AL mods for P-wave stuff !!!!!!!!!!!!!!!!!
                if (nrays>0) then
                    call sum_Ps_Pp_diff(r, vpv, vph, vsv, vsh, nptfinal, nrays, rayp, d_PsPp_prop, PsPp_error)
                    if (PsPp_error)  then
                        out=0
                        write(*,*)"INVALID PROPOSED MODEL - PsPp - Gradient or Nan likely"
                        goto 1142
                    end if
                end if

                lsd_PsPp_prop = 0
                liked_PsPp_prop = 0
                do i=1,nrays
                    lsd_PsPp_prop=lsd_PsPp_prop+(d_obsPsPp(i)-d_PsPp_prop(i))**2
                    liked_PsPp_prop=liked_PsPp_prop+(d_obsPsPp(i)-d_PsPp_prop(i))**2/(2*(Ad_PsPp_prop*d_obsPsPpe(i))**2)
                enddo
            end if

            
        endif 
        

        if (PsPp_flag==1) then
            like_prop=liked_R_prop+liked_L_prop+liked_PsPp_prop !log-likelihood of the proposed model
        else
            like_prop=liked_R_prop+liked_L_prop !log-likelihood of the proposed model
        end if
        
   1142 Accept = .false.
        
        ! now check if we accept the new model - different treatement depending on the change
        ! When out = 0 log(out) becomes nan so if statements yield false.
        if (birth) then!------------------------------------------------------------------
            if (vp_flag==0) then
                ! Vp Free
                if (log(ran3(ra))<log(out) + log(real(npt)+1)-log(real(npt_prop)+1) -&
                    log(2*width)-logprob_vsv-log(vp_max-vp_min)-logprob_vp&
                    -like_prop+like) then ! transdimensional case
                    accept=.true.
                    AcB=AcB+1
                endif
            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Vp scaled or Vp Fixed to ref
                if (log(ran3(ra))<log(out) + log(real(npt)+1)-log(real(npt_prop)+1) -&
                    log(2*width)-logprob_vsv&
                    -like_prop+like) then ! transdimensional case
                    accept=.true.
                    AcB=AcB+1
                endif
            end if
            
        elseif (death) then!-------------------------------------------------------------
        
            if (vp_flag==0) then
                ! Vp Free
                if (log(ran3(ra))<log(out) + log(real(npt)+1)&
                    -log(real(npt_prop)+1) + &
                    log(2*width)+logprob_vsv+log(vp_max-vp_min)+logprob_vp&
                    -like_prop+like) then! transdimensional case
                    accept=.true.
                    AcD=AcD+1
                endif
            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Vp scaled or Vp Fixed to ref
                if (log(ran3(ra))<log(out) + log(real(npt)+1)&
                    -log(real(npt_prop)+1) + &
                    log(2*width)+logprob_vsv&
                    -like_prop+like) then! transdimensional case
                    accept=.true.
                    AcD=AcD+1
                endif
            end if

        elseif (noisd_R) then !@@@@@@@@@@@@@@@@@@@@@@@@@@@@ logrsig  @@@@@@@@@@@@
            logrsig=ndatad_R*log(Ad_R/Ad_R_prop) ! ATTENTION avc ld 2
            if (log(ran3(ra))<logrsig+log(out)-like_prop+like) then ! hierarchical case
                accept=.true.
                Acnd_R=Acnd_R+1
            endif
        elseif (noisd_L) then !@@@@@@@@@@@@@@@@@@@@@@@@@@@@ logrsig  @@@@@@@@@@@@
            logrsig=ndatad_L*log(Ad_L/Ad_L_prop) ! ATTENTION avc ld 2
            if (log(ran3(ra))<logrsig+log(out)-like_prop+like) then ! hierarchical case
                accept=.true.
                Acnd_L=Acnd_L+1
            endif

        elseif (noisd_PsPp) then !@@@@@@@@@@@@@@@@@@@@@@@@@@@@ logrsig  @@@@@@@@@@@@
            if (PsPp_flag==0) then
                stop  'Should never go here if PsPp_flag==0'
            end if
            logrsig=nrays*log(Ad_PsPp/Ad_PsPp_prop) ! ATTENTION avc ld 2
            if (log(ran3(ra))<logrsig+log(out)-like_prop+like) then ! hierarchical case
                accept=.true.
                Acnd_PsPp=Acnd_PsPp+1
            endif     
   
        else !NO JUMP-------------------------------------------------------------------
    
            if (log(ran3(ra))<log(out)-like_prop+like)then
                if (ind>malayv) stop  '1082'
                accept=.true.
                if (value) then
                    AcV=AcV+1
                elseif (move) then
                    AcP=AcP+1
                elseif(ani)then
                    Acxi=Acxi+1
                elseif(change_vp)then
                    Ac_vp=Ac_vp+1        
                endif                    
                if (birtha) then
                    Acba=Acba+1
                elseif (deatha) then
                    Acda=Acda+1        
                endif
            endif!accept
        endif 
        
        !***********************************************************************************
        !   If we accept the proposed model, update the status of the Markov Chain
        !***********************************************************************************
        if (accept) then 
            isoflag=isoflag_prop
            voro=voro_prop
            like=like_prop
        
            liked_L=liked_L_prop
            liked_R=liked_R_prop
            lsd_L=lsd_L_prop
            lsd_R=lsd_R_prop
            npt=npt_prop
            Ad_R=Ad_R_prop
            Ad_L=Ad_L_prop
            
            d_cR=d_cR_prop
            d_cL=d_cL_prop
            
            if (lsd_R<lsd_R_min)then
                lsd_R_min = lsd_R
            endif
            if (lsd_L<lsd_L_min)then
                lsd_L_min = lsd_L
            endif
            
            if (PsPp_flag==1) then
                liked_PsPp=liked_PsPp_prop
                lsd_PsPp=lsd_PsPp_prop
                Ad_PsPp=Ad_PsPp_prop
                d_PsPp=d_PsPp_prop

                if (lsd_PsPp<lsd_PsPp_min)then
                    lsd_PsPp_min = lsd_PsPp
                endif
            end if

            !**********************************************************************
                
            !       Save best model
            
            !**********************************************************************
            
            if (PsPp_flag==1) then
                if ((lsd_L + lsd_R + lsd_PsPp).lt.likemax) then
                    voromax=voro
                    nptmax=npt
                    likemax=(lsd_L+lsd_R+lsd_PsPp)
                endif
            else
                if ((lsd_L+lsd_R).lt.likemax) then
                    voromax=voro
                    nptmax=npt
                    likemax=(lsd_L+lsd_R)
                endif
            end if

        endif

        npt_ani=0
        npt_iso=0
    
        do i=1,npt
            if (isoflag(i).eqv..true.) npt_iso=npt_iso+1
            if (isoflag(i).eqv..false.) npt_ani=npt_ani+1
        enddo
        if (npt_iso+npt_ani.ne.npt) stop "Error here"
        !****************************************************************

        !                  Store models for ensemble solution

        !****************************************************************
        ! Store models for restart
        IF ((mod(ount,store)==0)) THEN 
            write(number,1000)rank
            filename=number//'model.dat'
            open(rank*100,file=storename//'/'//filename,status='replace') 
            write(rank*100,*)nbproc
            write(rank*100,*)npt
            do i=1,npt
                write(rank*100,*)voro(i,:)
            enddo
            close(rank*100)
        ENDIF

        IF (ount.GT.burn_in) THEN
            sample=sample+1
            
            IF (mod(ount,thin)==0) THEN

                th_all=th_all+1
                
                call combine_linear_vp(model_ref,nptref,nic_ref,noc_ref,voro,npt,d_max,&
                r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,nptfinal,nic,noc,vs_data,xi,vp_data)   


                write(100,*)nptfinal-noc,npt,npt_ani
                write(100,*)Ad_R,Ad_L !,Ad_PsPp ! Need a new post processing again.
                do i=1,nptfinal-noc
                    write(100,*)(rearth-r(nptfinal+1-i))/1000.,vsv(nptfinal+1-i)&
                    ,xi(nptfinal+1-i),vph(nptfinal+1-i) ! vp_data(nptfinal+1-i) instead
                enddo
                write(100,*)like_prop
                !write(100,*)logalpha(:numdis)
                
                write(100,*)ndatad_R
                write(100,*)d_cR(:ndatad_R)
!                     do i=1,ndatad_R
!                         write(100,*)n_R(i),d_cR(i)
!                     enddo
                write(100,*)ndatad_L
                write(100,*)d_cL(:ndatad_L)
!                     do i=1,ndatad_L
!                         write(100,*)n_L(i),d_cL(i)
!                     enddo

                if (mod(th_all,everyall)==0) then
                close(100)
                write(filenamemax,"('/All_models_invert_',I3.3,'_',I3.3,'.out')") rank, sample/everyall
                open(100,file=mods_dirname//filenamemax,status='replace')
                write(100,*)rank,sample/everyall,everyall
                write(100,*)burn_in,nsample,thin
                write(100,*)d_min,d_max
                write(100,*)-width,width,vsref_min,vsref_max
                write(100,*)xi_min,xi_max
                write(100,*)vp_min,vp_max,vpref_min,vpref_max
                write(100,*)Ad_R_min,Ad_R_max
                write(100,*)Ad_L_min,Ad_L_max
                ! write(100,*)Ad_PsPp_min,Ad_PsPp_max ! Cant do this without changing post processing.
                endif

                ! average dispersion curve and variance
                d_cRmoy=d_cRmoy+d_cR*thin/nsample
                d_cLmoy=d_cLmoy+d_cL*thin/nsample
                d_cRdelta=d_cRdelta+(d_cR**2)*thin/nsample
                d_cLdelta=d_cLdelta+(d_cL**2)*thin/nsample
              
                if (PsPp_flag==1) then
                    d_PsPpmoy=d_PsPpmoy+d_PsPp*thin/nsample
                    d_PsPpdelta=d_PsPpdelta+(d_PsPp**2)*thin/nsample
                end if

                th = th + 1
                histo(npt)=histo(npt)+1 !histogram of number of layers
                
                ! call combine_linear_vp(model_ref,nptref,nic_ref,noc_ref,voro,npt,d_max,&
                !     r,rho,vpv,vph,vsv,vsh,qkappa,qshear,eta,nptfinal,nic,noc,vs_data,xi,vp_data)   
                j=1
                do i=disd,1,-1 ! average model
                    d=rearth-((i-1)*prof/real(disd-1))*1000.
                    
                    do while (r(j)<d)
                        j=j+1
                    end do
                    avvs(i)=avvs(i)+interp(r(j-1),r(j),vsv(j-1),vsv(j),d)
                    avxi(i)=avxi(i)+interp(r(j-1),r(j),xi(j-1),xi(j),d)
                    ! avvp(i)=avvp(i)+interp(r(j-1),r(j),vp_data(j-1),vp_data(j),d)
                    avvp(i)=avvp(i)+interp(r(j-1),r(j),vph(j-1),vph(j),d)
                    
                    if (abs(interp(r(j-1),r(j),xi(j-1),xi(j),d)-1.)>0.01) then
                        probani(i)=probani(i)+1
                    endif
                end do
                
                
                ! Write Posterior matrix!-----------------------------------------------------------------
                j=1
                
                do i=disd,1,-1
                    d=rearth-((i-1)*prof/real(disd-1))*1000.
                    
                    do while (r(j)<d)
                        j=j+1
                    end do
                    ind_vsv=ceiling((interp(r(j-1),r(j),vsv(j-1),vsv(j),d)-vsref_min)*disv/(vsref_max-vsref_min))
                    if (ind_vsv==0) ind_vsv=1
                    ind_xi =ceiling((interp(r(j-1),r(j),xi(j-1),xi(j),d)-xi_min)*disv/(xi_max-xi_min))
                    if (ind_xi==0) ind_xi=1
                    ! ind_vp=ceiling((interp(r(j-1),r(j),vp_data(j-1),vp_data(j),d)-vp_min)*disv/(vp_max-vp_min))
                    ind_vp=ceiling((interp(r(j-1),r(j),vph(j-1),vph(j),d)-vpref_min)*disv/(vpref_max-vpref_min))

                    if (ind_vp==0) ind_vp=1
                    if (ind_vsv<1)then
                        write(*,*)'ICI ICI ICI'
                        write(*,*)r(j-1),r(j),vsv(j-1),vsv(j),d
                        write(*,*)ind_vsv,i,interp(r(j-1),r(j),vsv(j-1),vsv(j),d),vsref_min,vsref_max,d
                        stop "vsv<disv"
                    endif
                    if (ind_vsv>disv) then
                        write(*,*)"vsv>disv"
                        write(*,*)interp(r(j-1),r(j),vsv(j-1),vsv(j),d),vsref_min,vsref_max
                        write(*,*)r(j-1),r(j),vsv(j-1),vsv(j),d
                        write(*,*)npt
                        write(*,*)voro(:,2)
                        stop "vsv>disv"
                    endif
                    !!!!!!!!!!!!!!!!!!!!!! NEED TO LOOK AT THIS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
                    if (ind_vp>disv) then
                        write(*,*)"vp>disv"
                        ! write(*,*)interp(r(j-1),r(j),vp_data(j-1),vp_data(j),d),vp_min,vp_max
                        write(*,*)interp(r(j-1),r(j),vph(j-1),vph(j),d),vpref_min,vpref_max
                        write(*,*)voro(:,4)
                        write(*,*)r(j-1),r(j),vph(j-1),vph(j),d
                        write(*,*)vp_data
                        write(*,*)j,i
                        stop "vp>disv"
                    endif
                    
                    if (ind_xi>disv) then
                        write(*,*)"xi>disv"
                        write(*,*)(interp(r(j-1),r(j),xi(j-1),xi(j),d)),xi_min,xi_max
                        write(*,*)voro(:,3)
                        write(*,*)r(j-1),r(j),xi(j-1),xi(j),d
                        write(*,*)xi
                        write(*,*)j,i
                        stop "xi>disv"
                    endif

                    postvs(i,ind_vsv)=postvs(i,ind_vsv)+1
                    if (ind_xi>0) postxi(i,ind_xi)=postxi(i,ind_xi)+1
                    if (ind_vp>0) postvp(i,ind_vp)=postvp(i,ind_vp)+1
                enddo

                i=ceiling((Ad_R-Ad_R_min)*disA/(Ad_R_max-Ad_R_min)) !histogram of Ad_R
                ML_Ad_R(i) = ML_Ad_R(i)+1
        
                i=ceiling((Ad_L-Ad_L_min)*disA/(Ad_L_max-Ad_L_min)) !histogram of Ad_L
                ML_Ad_L(i) = ML_Ad_L(i)+1
    
                if (PsPp_flag==1) then
                    i=ceiling((Ad_PsPp-Ad_PsPp_min)*disA/(Ad_PsPp_max-Ad_PsPp_min)) !histogram of Ad_PsPp
                    ML_Ad_PsPp(i) = ML_Ad_PsPp(i)+1
                end if

                !Get distribution on changepoint locations.
                
                do i=2,npt
                    j=ceiling((voro(i,1))*disd/(prof))
                    if (j.le.disd) histoch(j)=histoch(j)+1
                enddo	
                
                TRA(npt,npt_ani+1)=TRA(npt,npt_ani+1)+1
                if(npt_ani>npt) stop "npt_ani>npt"
                if(npt>malayv) stop "npt>malay" ! MODIF 
                if(npt_ani>malayv) stop "npt_ani>malay" ! MODIF
                
            endif
            !get convergence
            convBa(ount)=100*AcBa/PrBa ! acceptance rates in percent
            convB(ount)=100*AcB/PrB
            convDa(ount)=100*AcDa/PrDa
            convD(ount)=100*AcD/PrD

            convvs1(ount)=100*Acv/Prv
            convdp1(ount)=100*Acp/Prp
            
            if (vp_flag==0) then
                ! Vp Free
                convvp(ount)=100*Ac_vp/Pr_vp
            end if

            convxi(ount)=100*Acxi/Prxi
            convd_R(ount)=lsd_R
            convd_L(ount)=lsd_L
            ncell(ount)=npt
            convAd_R(ount)=Ad_R
            convAd_L(ount)=Ad_L

            if (PsPp_flag==1) then
                convd_PsPp(ount)=lsd_PsPp
                convAd_PsPp(ount)=Ad_PsPp
            end if

            do i=1,disd
                if (histoch(i)<0) write(*,*)'hahahahahahahahahh' !lol
            enddo

 
            !**********************************************************************
    
            !       Display what is going on every "Display" samples

            !**********************************************************************

        !write(*,*)ount

        endif
        
        IF ((mod(ount,display).EQ.0)) THEN ! .and.(mod(ran,50).EQ.0)) THEN

            write(*,*)'processor number',ran+1,'/',nbproc
            write(*,*)'sample:',ount,'/',burn_in+nsample
            write(*,*)'number of cells:',npt
            if (PsPp_flag==1) then
                write(*,*)'Ad_R',Ad_R,'Ad_L',Ad_L,'Ad_PsPp',Ad_PsPp
            else
                write(*,*)'Ad_R',Ad_R,'Ad_L',Ad_L
            end if
            write(*,*)'Acceptance rates'
            write(*,*)'AR_move',100*AcP/PrP
            write(*,*)'AR_value',100*AcV/PrV
            write(*,*)'AR_Birth',100*AcB/PrB,'AR_Death',100*AcD/PrD,'sigmav',sigmav,'sigmavp',sigmavp
            write(*,*)'AR_Birtha',100*AcBa/PrBa,'AR_Deatha',100*AcDa/PrDa
            write(*,*)'AR_xi',100*Acxi/Prxi,'pxi',pxi
            if (vp_flag==0) then
                ! Vp Free
                write(*,*)'AR_vp',100*Ac_vp/Pr_vp,'p_vp',p_vp
            elseif ((vp_flag==1).or.(vp_flag==2)) then
                ! Vp scaled or Fixed to ref
                write(*,*)'AR_vp, p_vp not relevant'
            end if
            write(*,*)'AR_Ad_R',100*Acnd_R/Prnd_R,'pAd_R',pAd_R
            write(*,*)'AR_Ad_L',100*Acnd_L/Prnd_L,'pAd_L',pAd_L
            if (PsPp_flag==1) then
                write(*,*)'AR_Ad_PsPp',100*Acnd_PsPp/Prnd_PsPp,'pAd_PsPp',pAd_PsPp
            end if
            write(*,*)'npt_iso',npt_iso,'npt_ani',npt_ani
            write(*,*)'recalculated',recalculated
            !write(*,*)Ar_birth_old,sigmav_old,sigmav
            write(*,*)'-----------------------------------------'
            write(*,*)
            write(*,*)
            
            recalculated=0
            
        END IF
        
    end do !End Markov chain
    
    close(100)

    ! best fitting model
    write(filenamemax,"('/bestmodel_',I3.3,'.out')") rank    
    open(56,file=mods_dirname//filenamemax,status='replace')
    write(56,*) nptmax,likemax
    do i=1,nptmax
        write(56,*)voromax(i,1),voromax(i,2),voromax(i,3),voromax(i,4)
    enddo
    close(56)
    
    k=0
    if (th.ne.0) then !normalize averages
        avvs=avvs/th
        avvp=avvp/th
        avxi=avxi/th
        probani=100*probani/th
        inorout(ran+1)=1
        k=k+1
    else
        write(*,*)
        write(*,*)'rank=',ran,'th=',th
        do k=325,350
            write(*,*)ran,probani(k),'%'
        enddo

    endif



    do i=1,nbproc
        call MPI_REDUCE(inorout,inorouts,21000,MPI_Integer,MPI_Sum,i-1,MPI_COMM_WORLD,ierror)
    enddo

    write(*,*)'rank=',ran,'th=',th

    j=0
    k=0
    do i=1,nbproc
        j=j+inorouts(i)
        if (inorouts(i).ne.0) then
            k=k+1
            members(k)=i-1
        endif
    enddo

    IF (ran==0) write(*,*) 'k',k,'nbproc',nbproc
    !***************************************************************************

    ! Collect information from all the chains and average everything

    !***************************************************************************
    flag=0
    do i=1,j
        if (ran==members(i)) flag=1
    enddo


    call MPI_Group_incl(group_world, j, members, good_group, ierror)
    !IF (ran==0) write(*,*)'1'
    !write(*,*)ran,members(1:9)
    call MPI_Comm_create(MPI_COMM_WORLD, good_group, MPI_COMM_small, ierror)
    !IF (ran==0) write(*,*)'2'

    do i=1,disd
        if (histochs(i)<0) write(*,*)'haaaaaaaaaaaaaaaaaaaaaaaa'
    enddo

    !-!
    if (flag==1) then
        call MPI_REDUCE(convBa,convBas,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convB,convBs,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convDa,convDas,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convD,convDs,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convvs1,convvs1s,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        ! call MPI_REDUCE(convvs2,convvs2s,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convdp1,convdp1s,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        ! call MPI_REDUCE(convdp2,convdp2s,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        if (vp_flag==0) then
            ! Vp Free
            call MPI_REDUCE(convvp,convvps,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        end if
        
        call MPI_REDUCE(convxi,convxis,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(histoch,histochs,disd,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(ML_Ad_R,ML_Ad_Rs,disA,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(ML_Ad_L,ML_Ad_Ls,disA,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(avvs,avvss,disd,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(avvp,avvps,disd,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(avxi,avxis,disd,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(probani,probanis,disd,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(postvs,postvss,disd*disv,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(postxi,postxis,disd*disv,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(postvp,postvps,disd*disv,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(ncell,ncells,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convd_R,convd_Rs,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convd_L,convd_Ls,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(histo,histos,malay,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(TRA,TRAs,malay*(malay+1),MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convAd_R,convAd_Rs,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(convAd_L,convAd_Ls,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        ! 
        call MPI_REDUCE(d_cRmoy,d_cRmoys,ndatadmax,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(d_cLmoy,d_cLmoys,ndatadmax,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(d_cRdelta,d_cRdeltas,ndatadmax,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        call MPI_REDUCE(d_cLdelta,d_cLdeltas,ndatadmax,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)


        if (PsPp_flag==1) then
            call MPI_REDUCE(ML_Ad_PsPp,ML_Ad_PsPps,disA,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
            call MPI_REDUCE(convd_PsPp,convd_PsPps,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
            call MPI_REDUCE(convAd_PsPp,convAd_PsPps,nsample+burn_in,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
            call MPI_REDUCE(d_PsPpmoy,d_PsPpmoys,nrays_max,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
            call MPI_REDUCE(d_PsPpdelta,d_PsPpdeltas,nrays_max,MPI_Real,MPI_Sum,0,MPI_COMM_small,ierror)
        end if


        do i=1,disd
            if (histochs(i)<0) write(*,*)'hiiiiiiiiiiiiiiiii'
        enddo

        d_cRmoys=d_cRmoys/j
        d_cLmoys=d_cLmoys/j
        d_cRdeltas=sqrt(d_cRdeltas/j-d_cRmoys**2)
        d_cLdeltas=sqrt(d_cLdeltas/j-d_cLmoys**2)
        
        if (PsPp_flag==1) then
            d_PsPpmoys=d_PsPpmoys/j
            d_PsPpdeltas=sqrt(d_PsPpdeltas/j-d_PsPpmoys**2)
        end if

        convPs=convPs/j
        convBs=convBs/j
        convBas=convBas/j
        convDs=convDs/j
        convDas=convDas/j
        convvs1s=convvs1s/j
        convdp1s=convdp1s/j
        convxis=convxis/j
        if (vp_flag==0) then
            ! Vp Free
            convvps=convvps/j
        end if
        
 
        probanis=probanis/j

        write(*,*)'rank=',ran,'th=',th

        avvss=avvss/j
        avvps=avvps/j
        avxis=avxis/j
        convd_Rs=convd_Rs/j
        convd_Ls=convd_Ls/j
        convAd_Rs=convAd_Rs/j
        convAd_Ls=convAd_Ls/j
        ncells=ncells/j

        if (PsPp_flag==1) then
            convd_PsPps=convd_PsPps/j
            convAd_PsPps=convAd_PsPps/j
        end if

    endif

    !***********************************************************************

    !                      Write the results

    !***********************************************************************


    IF (ran==members(1)) THEN

        open(65,file=dirname//'/Change_points.out',status='replace')
        do i=1,disd
            d=d_min+(i-0.5)*prof/real(disd)
            write(65,*)d,histochs(i)
        enddo
        close(65)

        open(95,file=dirname//'/Tradeoff.out',status='replace')
        write(95,*)malay
        do i=1,malay
            do j=1,malay+1
      
                write(95,*)TRAs(i,j)
            enddo
        enddo
        close(95)

        open(56,file=dirname//'/Average.out',status='replace')
        do i=1,disd
            d=(i-1)*prof/real(disd-1)
            write(56,*)d,avvss(i),avxis(i),avvps(i),probanis(i)
        enddo
        close(56)

        open(46,file=dirname//'/Sigmad_R.out',status='replace')
        write(46,*)Ad_R_min,Ad_R_max,disa
        do i=1,disA
            d=Ad_R_min+(i-0.5)*(Ad_R_max-Ad_R_min)/real(disA)
            write(46,*)d,ML_Ad_Rs(i)
        enddo
        close(46)

        open(47,file=dirname//'/Sigmad_L.out',status='replace')
        write(47,*)Ad_L_min,Ad_L_max,disa
        do i=1,disA
            d=Ad_L_min+(i-0.5)*(Ad_L_max-Ad_L_min)/real(disA)
            write(47,*)d,ML_Ad_Ls(i)
        enddo
        close(47)

        open(71,file=dirname//'/Dispersion_mean.out',status='replace')
        write(71,*)ndatad_R,ndatad_L
        do i=1,ndatad_R
            write(71,*)peri_R(i),n_R(i),d_cRmoys(i),d_cRdeltas(i)
        enddo
        do i=1,ndatad_L
            write(71,*)peri_L(i),n_L(i),d_cLmoys(i),d_cLdeltas(i)
        enddo
        close(71)
        
        open(71,file=dirname//'/Dispersion_obs.out',status='replace')
        write(71,*)ndatad_R,ndatad_L
        do i=1,ndatad_R
            write(71,*)peri_R(i),n_R(i),d_obsdcR(i),d_obsdcRe(i)
        enddo
        do i=1,ndatad_L
            write(71,*)peri_L(i),n_L(i),d_obsdcL(i),d_obsdcLe(i)
        enddo
        close(71)

        open(71,file=dirname//'/Posterior.out',status='replace')
        write(71,*)prof,disd,d_max
        ! write(71,*)vsref_min,vsref_max,disv,width,xi_min,xi_max,vp_min,vp_max
        write(71,*)vsref_min,vsref_max,disv,width,xi_min,xi_max,vpref_min,vpref_max
        ! write(71,*)-vs_max,vs_max,disv,width,xi_min,xi_max,-vp_max,vp_max
        
        do i=1,disd
            do j=1,disv
                write(71,*)postvss(i,j),postxis(i,j),postvps(i,j)
            enddo
        enddo
        close(71)

        open(54,file=dirname//'/Convergence_misfit.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            if (PsPp_flag==1) then
                write(54,*)convd_R(i),convd_Rs(i),convd_L(i),convd_Ls(i),convd_PsPp(i),convd_PsPps(i)
            else
                write(54,*)convd_R(i),convd_Rs(i),convd_L(i),convd_Ls(i)
            end if        
        enddo
        close(54)

        open(53,file=dirname//'/Convergence_nb_layers.out',status='replace')
        write(53,*)burn_in,nsample
        do i=1,nsample+burn_in
            write(53,*)ncell(i),ncells(i)
        enddo
        close(53)

        open(52,file=dirname//'/Convergence_sigma_R.out',status='replace')
        write(52,*)burn_in,nsample
        do i=1,nsample+burn_in
            write(52,*)convAd_R(i),convAd_Rs(i)
        enddo
        close(52)

        open(53,file=dirname//'/Convergence_sigma_L.out',status='replace')
        write(53,*)burn_in,nsample
        do i=1,nsample+burn_in
            write(53,*)convAd_L(i),convAd_Ls(i)
        enddo
        close(53)

        open(45,file=dirname//'/NB_layers.out',status='replace')
        do i=1,malay
            write(45,*)histos(i)
        enddo
        close(45)

        open(54,file=dirname//'/Convergence_Birth.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            write(54,*)convB(i),convBs(i),convBa(i),convBas(i)
        enddo
        close(54)
        
        open(54,file=dirname//'/Convergence_Death.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            write(54,*)convD(i),convDs(i),convDa(i),convDas(i)
        enddo
        close(54)
        
        open(54,file=dirname//'/Convergence_vs.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            write(54,*)convvs1(i),convvs1s(i)
        enddo
        close(54)
        
        open(54,file=dirname//'/Convergence_dp.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            write(54,*)convdp1(i),convdp1s(i)
        enddo
        close(54)
        

        if (vp_flag==0) then
            ! Vp Free
            open(54,file=dirname//'/Convergence_vp.out',status='replace')
            write(54,*)burn_in,nsample,burn_in,nsample
            do i=1,nsample+burn_in
                write(54,*)convvp(i),convvps(i)
            enddo
            close(54)
        elseif ((vp_flag==1).or.(vp_flag==2)) then
            ! Vp scaled or Fixed to ref
            write(*,*)'No Convergence_vp file to write...'
        end if

        open(54,file=dirname//'/Convergence_xi.out',status='replace')
        write(54,*)burn_in,nsample,burn_in,nsample
        do i=1,nsample+burn_in
            write(54,*)convxi(i),convxis(i)
        enddo
        close(54)

        if (PsPp_flag==1) then
            open(88,file=dirname//'/Sigmad_PsPp.out',status='replace')
            write(88,*)Ad_PsPp_min,Ad_PsPp_max,disa
            do i=1,disA
                d=Ad_PsPp_min+(i-0.5)*(Ad_PsPp_max-Ad_PsPp_min)/real(disA)
                write(88,*)d,ML_Ad_PsPps(i)
            enddo
            close(88)

            open(66,file=dirname//'/Convergence_sigma_PsPp.out',status='replace')
            write(66,*)burn_in,nsample
            do i=1,nsample+burn_in
                write(66,*)convAd_PsPp(i),convAd_PsPps(i)
            enddo
            close(66)

            open(71,file=dirname//'/PsPp_obs.out',status='replace')
            write(71,*)nrays
            do i=1,nrays
                write(71,*)rayp(i)*pi/180.0,d_obsPsPp(i),d_obsPsPpe(i)
            enddo
            close(71)

            open(71,file=dirname//'/PsPp_mean.out',status='replace')
            write(71,*)nrays
            do i=1,nrays
                write(71,*)rayp(i)*pi/180.0,d_PsPpmoys(i),d_PsPpdeltas(i)
            enddo
            close(71)
        end if

    endif
    CALL cpu_time(t2)
    if (ran==0) write(*,*)'time taken by the code was',t2-t1,'seconds'
    if (ran==0) write(*,*)'time taken by the code was',(t2-t1)/3600,'hours'

    call MPI_FINALIZE(ierror)! Terminate the parralelization


end! end the main program




!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



!----------------------------------------------------------------------

!               FUNCTIONS USED BY THE MAIN CODE  

!---------------------------------------------------------------------


!-------------------------------------------------------------------
!                        
!    Numerical Recipes random number generator for 
!       a Gaussian distribution
!
! ----------------------------------------------------------------------------



FUNCTION GASDEV(idum)

    !     ..Arguments..
    integer          idum
    real GASDEV

    !     ..Local..
    real v1,v2,r,fac
    real ran3
    if (idum.lt.0) iset=0
10  v1=2*ran3(idum)-1
    v2=2*ran3(idum)-1
    r=v1**2+v2**2
    if(r.ge.1.or.r.eq.0) GOTO 10
    fac=sqrt(-2*log(r)/r)
    GASDEV=v2*fac

    RETURN
END


!-------------------------------------------------------------------
!                        
!    Numerical Recipes random number generator
!
! ----------------------------------------------------------------------------

FUNCTION ran3(idum)
    INTEGER idum
    INTEGER MBIG,MSEED,MZ
    !     REAL MBIG,MSEED,MZ
    REAL ran3,FAC
    PARAMETER (MBIG=1000000000,MSEED=161803398,MZ=0,FAC=1./MBIG)
    !     PARAMETER (MBIG=4000000.,MSEED=1618033.,MZ=0.,FAC=1./MBIG)
    INTEGER i,iff,ii,inext,inextp,k
    INTEGER mj,mk,ma(55)
    !     REAL mj,mk,ma(55)
    SAVE iff,inext,inextp,ma
    DATA iff /0/
    ! write(*,*)' idum ',idum
    if(idum.lt.0.or.iff.eq.0)then
        iff=1
        mj=MSEED-iabs(idum)
        mj=mod(mj,MBIG)
        ma(55)=mj
        mk=1
        do 11 i=1,54
            ii=mod(21*i,55)
            ma(ii)=mk
            mk=mj-mk
            if(mk.lt.MZ)mk=mk+MBIG
            mj=ma(ii)
        !  write(*,*)' idum av',idum
11      continue
        do 13 k=1,4
            do 12 i=1,55
                ma(i)=ma(i)-ma(1+mod(i+30,55))
                if(ma(i).lt.MZ)ma(i)=ma(i)+MBIG
12          continue
13      continue
        ! write(*,*)' idum ap',idum
        inext=0
        inextp=31
        idum=1
    endif
    ! write(*,*)' idum app ',idum
    inext=inext+1
    if(inext.eq.56)inext=1
    inextp=inextp+1
    if(inextp.eq.56)inextp=1
    mj=ma(inext)-ma(inextp)
    if(mj.lt.MZ)mj=mj+MBIG
    ma(inext)=mj
    ran3=mj*FAC
    !  write(*,*)' idum ',idum
    
    return
END

!-------------------------------------------------------------------
!                        
!    Function to calculate dVp scaling factor based on depth
!     See Ritsema et al., 2011 GJI - S40RTS model
! 
! ----------------------------------------------------------------------------


FUNCTION vp_scale_S40(m_depth)

    !     ..Arguments..
    real m_depth ! depth in the mantle
    real vp_scale_S40     ! Vsv,vph perturbations

    vp_scale_S40=1.0/(m_depth/2891.0+2.0)

END FUNCTION vp_scale_S40



!the code is finished. 
