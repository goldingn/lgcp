##' neigh2D function
##'
##' A function to compute the neighbours of a cell on a toral grid
##'
##' @param i cell index i
##' @param j cell index j
##' @param ns number of neighbours either side
##' @param M size of grid in x direction
##' @param N size of grid in y direction
##' @return the cell indices of the neighbours
##' @export
neigh2D <- function(i,j,ns,M,N){ # returns neighbours on a toral grid of size M x N
    xid <- (i-ns):(i+ns)
    yid <- (j-ns):(j+ns)
    n <- 2*ns + 1
    neigh <- cbind(rep(xid,n),rep(yid,each=n))
    neigh[,1] <- neigh[,1]%%M
    neigh[,1][neigh[,1]==0] <- M
    neigh[,2] <- neigh[,2]%%N
    neigh[,2][neigh[,2]==0] <- N
    return(neigh)
}

##' paramprecbase function
##'
##' A function to compute the parametrised base matrix of a precision matrix of a GMRF on an M x N toral grid with neighbourhood size ns. Note that 
##' the precision matrix is block circulant. The returned function operates on a parameter vector as in Rue and Held (2005) pp 187.
##'
##' @param ns neighbourhood size
##' @param M number of x cells
##' @param N number of y cells
##' @param inverse whether or not to compute the base matrix of the inverse precision matrix (ie the covariance matrix). default is FALSE
##' @return a functioin that returns the base matrix of the precision matrix
##' @export
paramprecbase <- function(ns,M,N,inverse=FALSE){
    nn <- (2*ns+1)^2 # number of neighbours
    mp <- median(1:nn) # the middle cell index
    idx <- neigh2D(1,1,ns=ns,M=M,N=N)
    nz <- matrix(1:(M*N),M,N)[idx] # non zero
    d1 <- pmin(abs(idx[,1]-idx[mp,1]),M-abs(idx[,1]-idx[mp,1]))
    d2 <- pmin(abs(idx[,2]-idx[mp,2]),N-abs(idx[,2]-idx[mp,2]))
    d <- sqrt(d1^2 + d2^2)
    rd <- rank(d) # deals with ties in distance
    rdlevs <- sort(unique(rd))
    idxlist <- sapply(rd,function(x){which(rdlevs==x)})
    np <- length(rdlevs)
    if (!inverse){
        bcb <- function(theta){ # note v is assumed to represent (theta_1,theta_2,...,theta_np) as in Rue and Held (2005) pp 187
            if(length(theta)!=np){
                stop(paste("Error in paramprecbase: length of theta must be",np))
            }
            ment <- rep(0,N*M)
            ment[nz] <- theta[idxlist]
            return(matrix(ment,M,N))
        }
    }
    else{
        bcb <- function(theta){ # note v is assumed to represent (theta_1,theta_2,...,theta_np) as in Rue and Held (2005) pp 187
            if(length(theta)!=np){
                stop(paste("Error in paramprecbase: length of theta must be",np))
            }
            ment <- rep(0,N*M)
            ment[nz] <- theta[idxlist]
            return(inversebase(matrix(ment,M,N)))
        }
    }
    attr(bcb,"npar") <- np
    #attr(bcb,"toraldistx") <- d1 # these are not needed
    #attr(bcb,"toraldisty") <- d2
    #attr(bcb,"nonzero") <- nz
    #attr(bcb,"idxlist") <- idxlist  
    return(bcb)
}

##' paramprec function
##'
##' A function to compute the precision matrix of a GMRF on an M x N toral grid with neighbourhood size ns. Note that 
##' the precision matrix is block circulant. The returned function operates on a parameter vector as in Rue and Held (2005) pp 187.
##'
##' @param ns neighbourhood size
##' @param M number of cells in x direction
##' @param N number of cells in y direction
##' @return a function that returns the precision matrix given a parameter vector.
##' @export
paramprec <- function(ns,M,N){
    precbase <- paramprecbase(ns=ns,M=M,N=N)
    prec <- function(theta){
        return(circulant(precbase(theta)))
    }
    return(prec)
}

##' matchcovariance function
##'
##' A function to match the covariance matrix of a Gaussian Field with an approximate GMRF with neighbourhood size ns.
##'
##' @param xg x grid must be equally spaced
##' @param yg y grid must be equally spaced
##' @param ns neighbourhood size
##' @param sigma spatial variability parameter
##' @param phi spatial dependence parameter
##' @param model covariance model, see ?CovarianceFct
##' @param additionalparameters additional parameters for chosen covariance model
##' @param verbose whether or not to print stuff generated by the optimiser
##' @param r parameter used in optimisation, see Rue and Held (2005) pp 188. default value 1.
##' @param method The choice of optimising routine must either be 'Nelder-Mead' or 'BFGS'. see ?optim
##' @return ...
##' @export
matchcovariance <- function(xg,yg,ns,sigma,phi,model,additionalparameters,verbose=TRUE,r=1,method="Nelder-Mead"){
    if(is.na(match(method,c("Nelder-Mead","BFGS")))){
        stop("Method must either be 'Nelder-Mead' or 'BFGS'")
    }
    bcb <- blockcircbase(x=xg,y=yg,sigma=sigma,phi=phi,model=model,additionalparameters=additionalparameters,inverse=FALSE) # base matrix of the covariance. note inverse=FALSE here
    M <- length(xg)
    N <- length(yg)
    ippb <- paramprecbase(ns=ns,M=M,N=N,inverse=TRUE) # parametrised base matrix of the covariance. note inverse=TRUE here (compare with above)
    ppb <- paramprecbase(ns=ns,M=M,N=N,inverse=FALSE) # parametrised base matrix of the precision, used in computing gradient
    init <- rep(0,attr(ippb,"npar"))
    init[1] <- 1/bcb[1,1]
    xdiv <- xg[2] - xg[1]
    ydiv <- yg[2] - yg[1]
    idx <- which(matrix(TRUE,M,N),arr.ind=TRUE)
    d1 <- pmin(abs(idx[,1]-idx[1,1]),M-abs(idx[,1]-idx[1,1]))
    d2 <- pmin(abs(idx[,2]-idx[1,2]),N-abs(idx[,2]-idx[1,2]))
    d <- sqrt((xdiv*d1)^2+(xdiv*d2)^2)
    w <- (1+r/d)/d
    w[d==0] <- 1
    w <- matrix(w,M,N)
    #browser()
    optfun <- function(theta){
        if(verbose){
            print(theta)
        }
        if(any(sign(eigenfrombase(ippb(theta)))==-1)){ # test if SPD
            return(NA)
        }
        return(sum(w*(bcb-ippb(theta))^2))
    }
    gradfun <- function(theta){ # gradient function Rue and Held pp 190
        diff <- c()
        for (i in 1:length(theta)){
            thetadrv <- rep(0,length(theta))
            thetadrv[i] <- 1
            deriv <- (1/(M*N))*Re(fft(-(1/(M*N))*(Re(fft(ppb(theta)))^(-2))*Re(fft(ppb(thetadrv))),inverse=TRUE)) # Equation (5.11) pp. 190 Rue and Held 2005
            diff[i] <- -2*sum(w*(bcb-ippb(theta))*deriv)
        }
        return(diff)
    }
    start <- Sys.time()
    if (verbose){
        if (method=="Nelder-Mead"){
            opt <- optim(init,optfun,control=list(trace=1000),method=method)
        }
        if (method=="BFGS"){
            opt <- optim(init,optfun,gradfun,control=list(trace=1000),method=method)
        }    
    }
    else{
        if (method=="Nelder-Mead"){
            opt <- optim(init,optfun,method=method)
        }
        if (method=="BFGS"){
            opt <- optim(init,optfun,gradfun,method=method)
        }    
    }
    end <- Sys.time()
    cat("Optimiser took",difftime(end,start,units="secs"),"seconds\n")
    ans <- ippb(opt$par)
    attr(ans,"par") <- opt$par
    attr(ans,"precbase") <- paramprecbase(ns=ns,M=M,N=N)(opt$par)
    attr(ans,"timetaken") <- difftime(end,start,units="secs")
    attr(ans,"optinfo") <- opt

    if(!is.SPD(ans)){
        warning("Returned matrix is not SPD, consider setting testSPD=TRUE",.immediate=TRUE)
    }
    return(ans)
}

##' sparsebase function
##'
##' A function that returns the full precision matrix in sparse format from the base of a block circulant matrix, see ?Matrix::sparseMatrix
##'
##' @param base base matrix of a block circulant matrix
##' @return ...
##' @export
sparsebase <- function(base){
    M <- dim(base)[1]
    N <- dim(base)[2]
    vecb <- as.vector(base)
    block <- rep(1:N,each=M)
    idx <- which(vecb!=0) # which are the non zero entries in the first row?
    n <- length(idx)
    vb <- vecb[idx] # the actual entries
    bl <- block[idx] # block index
    blmin <- M*(bl-1)+1
    blmax <- M*bl
    blockrow <- vb
    jidx <- idx
    iidx <- rep(1,n)
    vec <- as.numeric(table(bl))
    names(vec) <- c()
    vbidx <- 1:length(vb)
    tbl <- table(bl)
    vbbl <- as.vector(sapply(1:length(tbl),function(x){rep(x,tbl[x])}))
    vbblmax <- sapply(1:length(tbl),function(x){rev(which(vbbl==x))[1]})
    vbblmax <- as.vector(sapply(1:length(tbl),function(x){rep(vbblmax[x],tbl[x])}))
    for (i in 2:M){
        vbcand <- (vbidx+1)%%vbblmax
        vbcand[vbcand==0] <- vbblmax[vbcand==0]
        cand <- (idx+1)%%(M*bl)
        cand[cand==0] <- blmax[cand==0]
        idx <- pmax(cand,blmin)
        blockrow <- c(blockrow,vb[vbidx])
        jidx <- c(jidx,idx)
        iidx <- c(iidx,rep(i,n))
    }
    len <- length(iidx)
    newj <- jidx
    for(i in 2:N){
        iidx <- c(iidx,iidx[1:len]+(i-1)*M)
        newj <- (newj+M)%%(N*M)
        newj[newj==0] <- N*M
        jidx <- c(jidx,newj)
    }
    blockrow <- rep(blockrow,N)
    return(sparseMatrix(i=iidx,j=jidx,x=blockrow))
}



##' meanfield.lgcpPredictINLA function
##'
##' A function to return the mean of the latent field from a call to lgcpPredictINLA output.
##'
##' @method meanfield lgcpPredictINLA
##' @param obj an object of class lgcpPredictINLA
##' @param ... other arguments 
##' @return the mean of the latent field
##' @export
meanfield.lgcpPredictINLA <- function(obj,...){
    return(obj$mu + matrix(obj$inlaresult$summary.random$index$mean,obj$ext*obj$M,obj$ext*obj$N)[1:obj$M,1:obj$N]) # note have to add mu back in here  
}


##' varfield.lgcpPredictINLA function
##'
##' A function to return the variance of the latent field from a call to lgcpPredictINLA output. 
##'
##' @method varfield lgcpPredictINLA
##' @param obj an object of class lgcpPredictINLA
##' @param ... other arguments 
##' @return the variance of the latent field
##' @export
varfield.lgcpPredictINLA <- function(obj,...){
    return(matrix(obj$inlaresult$summary.random$index$sd,obj$ext*obj$M,obj$ext*obj$N)[1:obj$M,1:obj$N])   
}


##' getlgcpPredictSpatialINLA function
##'
##' A function to download and 'install' lgcpPredictSpatialINLA into the lgcp namespace.
##'
##' @return Does not return anything
##' @export
getlgcpPredictSpatialINLA <- function(){
    source("http://www.lancs.ac.uk/staff/taylorb1/lgcpPredictSpatialINLA.R")
    assignInNamespace("lgcpPredictSpatialINLA",lgcpPredictSpatialINLA,"lgcp")
    cat("lgcpPredictSpatialINLA successfully installed.\n")
}    
