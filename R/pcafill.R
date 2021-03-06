## Script for filling in missing values using PCA. This makes sense
## for situations where the data to a large extent is accounted for
## by a few leading PCs/modes.

## Function for one time series based on multiple regression
## Allow EOFs with different number of PCs.
fitpc <- function(y,x,eofs=1:4) {
  caldat <- data.frame(y=y,x)
  #print(summary(caldat))
  eofs <- eofs[eofs <=dim(x)[2]]
  fitstr <- paste('y ~ ',paste('X.',eofs,sep='',collapse=' + '))
  fit <- eval(parse(text=paste('lm(',fitstr,', data=caldat)')))
  z <- predict(fit,newdata=caldat)
  invisible(z)
}

eoffit <- function(X,U,eofs) {
  ## Use regression to project the pattern of observations onto the PCA pattern and estimate
  ## the PCs.
  caldat <- data.frame(X=X,U=U)
  names(caldat) <- c('X',paste('U.',eofs,sep=''))
  #print(names(caldat))
  calexpr <- paste('X ~ ',paste('U.',eofs,sep='',collapse=' + '))
  eval(parse(text=paste('projection <- lm(',calexpr,',data=caldat)')))
  V <- projection$coefficients
  invisible(V[-1])
}

# Redundant:
#fillmiss <- function(y,x,neofs=7) {
#  z <- apply(coredata(y),2,fitpc,coredata(x),neofs=neofs)
#  invisible(z)
#}

pcafill <- function(X,insertmiss=0,eofs=1:4,mnv=0,complete=FALSE,test=FALSE,verbose=FALSE) {
  if (verbose) print('pcafill')
  X0 <- X ## For debugging
  if (verbose) print(dim(X0))
  if (insertmiss>0) {
    ## Test by inserting false missing values in the data
    if (verbose) print(paste('Test: insert',insertmiss,'NAs'))
    x <- c(coredata(X))
    ok <- is.finite(x)
    ## Only replace valid data
    xok <- x[ok]
    ## Pick random samples
    isx <- order(rnorm(sum(ok)))[1:insertmiss]
    if (verbose) print(c(isx,sum(ok)))
    ## Save the original data set to NA
    x0 <- xok[isx]
    ## Set theselected data points ot NA
    xok[isx] <- NA
    ## Replace the data with that with introduced NAs
    x[ok] <- xok
    dim(x) <- dim(X)
    coredata(X) <- x
    if (verbose) print('---')
  }
  nok <- apply(X,1,nv)
  ## Remove the years with no (of little) data
  X <- subset(X,it=nok > mnv)
  if (verbose) print(dim(X))
  mok <- apply(X,2,nv)

  if (verbose) print(paste(sum(nok>mnv),'stations with',
                           sum(mok>0),'data points'))
  if (sum(mok==length(index(X))) <= 1)
    stop('pcafill: Too many missing data or too small set of stations')
  
  ## PCA for stations with complete data
  pca <- PCA(subset(X,is=mok==length(index(X))),n=max(eofs))

  ## Y contains the more complete data set - copy all the attributes from X
  Y <- X
  ## Replace the data in Y with predicted based on the PCA
  #  coredata(Y) <- fillmiss(X,pca,neofs=neofs)
  coredata(Y) <- apply(coredata(X),2,fitpc,coredata(pca),eofs=eofs)

  if (complete) {
    print("UNFINISHED")
    if (verbose) print('Projection to provide complete dataset')
    if (verbose) print(dim(Y))
    ## Projection of patterns onto the original data to get a more complete data set
    ## X0 = U W t(V) -> estimate new t(V) based on U & W from Y
    ## 1/W t(U) X0 = t(V) -> V = t(X0) U /W
    pcax <- PCA(Y); pcax <- subset(pcax,pattern=eofs)
    U <- attr(pcax,'pattern'); W <- attr(pcax,'eigenvalues')
    U <-  U %*% diag(W)
    XX <- X0
    XX <- t(t(XX) - rowMeans(XX,na.rm=TRUE))
    ## Estimate the PCs for the entire data set through projection:
    Vx <- zoo(t(apply(t(coredata(XX)),2,eoffit,U=U,eofs=eofs)),order.by=index(X0))
    ## assign the attributes from the PCA
    Vx <- attrcp(pcax,Vx); class(Vx) <- class(pcax) 
    plot.zoo(pca[,1]); lines(Vx[,1],col='red'); browser()
    ## Reconstruct the data:
    Y <- pca2station(Vx,verbose=verbose)
  }
  
  if (insertmiss>0) {
    if (verbose) print('Assess the test results')
    ## For testing, extract the data points replaced by NAs
    if (test) y <- c(coredata(X0)) else ## For debugging
              y <- c(coredata(Y))
    ## Use the same points with valid data
    yok <- y[ok]
    if (verbose) print(sum(!is.finite(xok[isx])))
    y0 <- yok[isx]
    if (sum(insertmiss)>1) {
      xy0 <- cbind(x0,y0); colnames(xy0) <- c('original','predicted')
    } else {
      xy0 <- c(x0,y0); names(xy0) <- c('original','predicted')
    }
    
    if ( (test) & (sum(is.element(x0,y0)) != length(x0)) )
      warning('The test results should be identical!')
    if (verbose) print(xy0)
    if (!is.null(attr(Y,'na.test')))
        attr(Y,'na.test') <- rbind(attr(Y,'na.test'),xy0) else
        attr(Y,'na.test') <- xy0
  }
  invisible(Y)
}

pcafill.test <- function(X,N=100,max.miss=100,eofs=1:4,verbose=FALSE) {
  insertmiss <- round(runif(N)*max.miss)
  insertmiss[insertmiss<1] <- 2
  par(bty='n')
  plot(range(c(coredata(X)),na.rm=TRUE),
       range(c(coredata(X)),na.rm=TRUE),
       type='l',lwd=3,col='grey30',
       xlab='original',ylab='predicted',
       main='Test of prediction of missing values',
       sub="NA's randomly inserted")
  grid()
  for (i in 1:N) {
    if (verbose) print(insertmiss[i])
    Y.test <- pcafill(X,insertmiss=insertmiss[i],eofs=eofs,verbose=verbose)
    points(attr(Y.test,'na.test'),pch=19,col=rgb(0,0,0.6,0.1))
    if (i==1) test.res <- attr(Y.test,'na.test') else
              test.res <- rbind(test.res,attr(Y.test,'na.test'))
  }
  invisible(test.res)
}
