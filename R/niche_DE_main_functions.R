#' Niche_DE
#'
#' This function performs niche-DE
#' @param object A niche-DE object
#' @param C Minimum total expression of a gene needed for the model to run. Default value is 150.
#' @param M Minimum number of spots containing the index cell type with the
#' niche cell type in its effective niche for (index,niche) niche patterns
#' to be investigated. Default value is 10.
#' @param gamma Percentile a gene needs to be with respect to expression in the
#'  index cell type in order for the model to investigate niche patterns for
#'  that gene in the index cell. Default value is 0.8 (80th percentile)
#' @param print Logical if function should print progress report (kernel, gene #)
#' @return A niche-DE object with niche-DE analysis performed
#' @export
niche_DE = function(object,C = 150,M = 10,gamma = 0.8,print = T){
  #starting Message
  print(paste0('Starting Niche-DE analysis with parameters C = ',C,', M = ',M,', gamma = ', gamma,'.'))
  #initialize list output
  object@niche_DE = vector(mode = "list", length = length(object@sigma))
  names(object@niche_DE) = object@sigma
  counter = 1
  valid = matrix(0,ncol(object@counts),length(object@sigma))
  #iterate over each sigma value
  for(sig in object@sigma){
    print(paste0('Performing Niche-DE analysis with kernel bandwidth:',sig,' (number ',counter,' out of ',length(object@sigma),' values)'))
    #get expression filter (gamma)
    CT_filter = apply(object@ref_expr,1,function(x){quantile(x,gamma)})
    #initialize p value array
    ngene = ncol(object@counts)
    n_type = ncol(object@num_cells)
    dimnames = list(A = colnames(object@num_cells),B  = colnames(object@num_cells), C = colnames(object@counts))
    #pgt is index type by niche type by gene
    T_stat = array(NA,c(n_type,n_type,ngene),dimnames = dimnames)
    var_cov = array(NA,c(n_type^2,n_type^2,ngene))
    betas = array(NA,c(n_type,n_type,ngene),dimnames = dimnames)
    liks = rep(NA,ngene)
    for(j in c(1:ngene)){
      if(j%%1000 == 0 & print == T){
        print(paste0('kernel bandwidth:', sig,' (number ',counter,' out of ',length(object@sigma),' values), ', "Processing Gene #",j,
                     ' out of ',ncol(object@counts)))
      }
      #do if  gene is rejected and gene-type has at least 1 rejection
      if((sum(object@counts[,j])>C)&(mean(object@ref_expr[,j]<CT_filter)!=1)){
        #get pstg matrix
        pstg = object@num_cells%*%as.matrix(diag(object@ref_expr[,j]))/object@null_expected_expression[,j]
        pstg[,object@ref_expr[,j]<CT_filter] = 0
        pstg[pstg<0.05]=0
        #get X
        #print(1)
        X = matrix(NA,nrow(pstg),n_type^2)
        for(k in c(1:nrow(pstg))){
          #get feature matrix by multiplying effective niche and pstg vector
          ps = as.matrix(pstg[k,])
          EN_j = round(object@effective_niche[[counter]][k,],2)
          cov_j = ps%*%t(EN_j)
          #make into a vector
          X[k,] = as.vector(t(cov_j))#important to take the transpose
        }
        #get index, niche pairs that are non existent
        null = which(apply(X,2,function(x){sum(x>0)})<M)
        X_partial = X
        rest = c(1:ncol(X))
        if(length(null)>0){
          X_partial = X[,-null]
          rest = rest[-null]
        }
        #continue if at least one index,niche pair is viable
        if(length(null)!=n_type^2){
          tryCatch({
            #if expected expression for a spot is 0, remove it
            bad_ind  = which(object@null_expected_expression[,j]==0)
            #print('Running GLM')
            #run neg binom regression
            #print(2)
            if(length(bad_ind)>0){
              full_glm =suppressWarnings({glm(object@counts[-bad_ind,j]~X_partial[-bad_ind,] + offset(log(object@null_expected_expression[-bad_ind,j])), family = "poisson")}) #do full glm
            }else{
              full_glm = suppressWarnings({glm(object@counts[,j]~X_partial + offset(log(object@null_expected_expression[,j])), family = "poisson")}) #do full glm
            }
            mu_hat = exp(predict(full_glm))#get mean
            #get dicpersion parameter
            A = optimize(nb_lik,x = object@counts[,j],mu = mu_hat, lower = 0.05, upper = 100) #get overdispersion parameter
            #save dispersion parameter
            disp = A$minimum
            #save likelihood
            liks[j] = -A$objective
            #calculate W matrix for distribution of beta hat
            W =as.vector(mu_hat/(1 + mu_hat/disp))#get W matrix
            #print(3)
            #perform cholesky decomp for finding inverse of X^TWX
            if(length(bad_ind)>0){
              X_partial = as((X_partial[-bad_ind,]),"sparseMatrix")
              #remove bad indices
            }else{
              X_partial = as((X_partial),"sparseMatrix")
            }
            #get variance matrix
            var_mat = Matrix::t(X_partial*W)%*%X_partial
            #if there are degenerate columns, remove them
            new_null = c()
            if(length(bad_ind)>0){
              new_null = which(diag(as.matrix(var_mat))==0)
              if(length(new_null)>0){
                var_mat = var_mat[-new_null,-new_null]
                null = sort(c(null,rest[new_null]))
              }
            }
            if(length(null)!=n_type^2){
              #cholesky decomposition
              A = Matrix::chol(var_mat,LDL = FALSE,perm = FALSE)
              #get covaraince matrix
              V = solve(A)%*%Matrix::t(solve(A))
              #get standard devaition vector
              tau = sqrt(diag(V))#get sd matrix
              V_ = matrix(NA,n_type,n_type)
              if(length(null)==0){
                V_ = matrix(tau,n_type,n_type)
              }else{
                V_[c(1:n_type^2)[-null]] = tau}
              #for full var_cov matrix.
              v_cov = matrix(NA,n_type^2,n_type^2)
              if(length(null)==0){
                v_cov = matrix(V,n_type^2,n_type^2)
              }else{
                v_cov[-null,-null] = as.matrix(V)}
              #print('getting beta')
              beta = matrix(NA,n_type,n_type)

              if(length(new_null)>0){
                beta[c(1:n_type^2)[-null]] = full_glm$coefficients[-c(1,new_null+1)]
              }

              if(length(new_null)==0){
                if(length(null)==0){
                  beta = matrix(full_glm$coefficients[-c(1)],n_type,n_type)
                }else{
                  beta[c(1:n_type^2)[-null]] = full_glm$coefficients[-c(1)]}
              }
              #record test statitistic
              T_ = Matrix::t(beta/V_)
              T_stat[,,j] = T_
              betas[,,j] = Matrix::t(beta)
              var_cov[,,j] = v_cov
              valid[j,counter] = 1
            }
            #end of if statement
            }, #get pval
              error = function(e) {
              skip_to_next <<- TRUE})
        }
      }
    }
    #save object
    object@niche_DE[[counter]] = list(T_stat = T_stat,beta = betas,var_cov = var_cov,log_lik = liks)
    counter = counter + 1
  }
  #get column sums of counts matrix to see how many genes pass filtering
  A = rowSums(valid)
  #get number of genes that pass filtering
  num_pass = sum(A>=1,na.rm = T)
  print('Computing Niche-DE Pvalues')
  object = get_niche_DE_pval(object,pos = T)
  object = get_niche_DE_pval(object,pos = F)
  print(paste0('Niche-DE analysis complete. Number of Genes with niche-DE T-stat equal to ',num_pass))
  if(num_pass < 1000){
    warning('Less than 1000 genes pass. This could be due to insufficient read depth of data or size of C parameter. Consider changing choice of C parameter')
  }
  return(object)
}



#' Get niche genes for the given index and niche cell types at the desired test.level
#'
#' This function returns genes that show niche patterns at the desired test.level
#'
#' @param object A niche-DE object
#' @param test.level At which test.level to return genes
#' (gene level, cell type level, interaction level)
#' @param index The index cell type
#' @param niche The niche cell type
#' @param direction Character indicating whether to return genes that are (index,niche)+
#' patterns (direction = 'positive') or (index,niche)- (direction = 'negative'). Default value is 'positive'.
#' @param alpha The level at which to perform the Benjamini Hochberg correction. Default value = 0.05
#' @return A vector of genes that are niche significant at the desired FDR,
#' test.level, index cell type, and niche cell type
#' @export
get_niche_DE_genes = function(object,test.level,index,niche,direction = 'positive',alpha = 0.05){
  if((test.level %in% c('gene','cell type','interaction'))==F){
    stop('test.level must be one of gene, cell type, or interaction')
  }

  if((direction %in% c('positive','negative'))==F){
    stop('direction must be one of positive or negative')
  }

  if(direction == 'positive'){
    S = '+'
  }else{
    S = '-'
  }
  if(test.level == 'interaction'){
    print(paste0('Finding Niche-DE',S,' genes at the interaction level between index cell type ',index,' and niche cell type '
           ,niche,'. Performing BH procedure at level ',alpha,'.'))
  }
  if(test.level == 'cell type'){
    print(paste0('Finding Niche-DE',' genes at the cell type level in index cell type ',index,'. Performing BH procedure at level ',alpha,'.'))
  }
  if(test.level == 'gene'){
    print(paste0('Finding Niche-DE',' genes at the gene level','. Performing BH procedure at level ',alpha,'.'))
  }

  #if test.level if gene level
  if(test.level=='gene' & direction == 'positive'){
    #get genes that reject at gene level
    gene_ind = which(object@niche_DE_pval_pos$gene_level<(alpha))
    genes = object@gene_names[gene_ind]
    #get associated pvalues
    pval = object@niche_DE_pval_pos$gene_level[gene_ind]
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Gene')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }

  if(test.level=='gene' & direction == 'negative'){
    #get genes that reject at gene level
    gene_ind = which(object@niche_DE_pval_neg$gene_level<(alpha))
    genes = object@gene_names[gene_ind]
    #get associated pvalues
    pval = object@niche_DE_pval_neg$gene_level[gene_ind]
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Gene')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }



  if((index %in% colnames(object@num_cells))=='negative'){
    stop('Index cell type not found')
  }

  #get index and nice indices
  ct_index = which(colnames(object@num_cells)==index)
  niche_index = which(colnames(object@num_cells)==niche)
  #check to see if they have enough overlap
  colloc = check_colloc(object,ct_index,niche_index)
  for(value in c(1:length(colloc))){
    if(colloc[value]<30){
      warning('Less than 30 observations containing collocalization of ',index,
              ' and ',niche,' at kernel bandwidth ',names(colloc)[value],
              '. Results may be unreliable.')
    }
  }
  #if test.level if cell type level
  if(test.level=='cell type' & direction == 'positive'){
    #get index of index cell type
    ct_index = which(colnames(object@num_cells)==index)
    #get genes that reject at the gene and CT level
    gene_index = which((object@niche_DE_pval_pos$gene_level<(alpha)) & (object@niche_DE_pval_pos$cell_type_level[,ct_index]<(alpha)))
    genes = object@gene_names[gene_index]
    #get associated pvalues
    pval = object@niche_DE_pval_pos$cell_type_level[gene_index,ct_index]
    #save results
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Cell.Type')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }

  if(test.level=='cell type' & direction == 'negative'){
    #get index of index cell type
    ct_index = which(colnames(object@num_cells)==index)
    #get genes that reject at the gene and CT level
    gene_index = which((object@niche_DE_pval_neg$gene_level<(alpha)) & (object@niche_DE_pval_neg$cell_type_level[,ct_index]<(alpha)))
    genes = object@gene_names[gene_index]
    #get associated pvalues
    pval = object@niche_DE_pval_neg$cell_type_level[gene_index,ct_index]
    #save results
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Cell.Type')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }

  if((niche %in% colnames(object@num_cells))==F){
    stop('Niche cell type not found')
  }

  #if test.level if interaction level
  if(test.level =='interaction' & direction=='positive'){
    ct_index = which(colnames(object@num_cells)==index)
    niche_index = which(colnames(object@num_cells)==niche)
    gene_index = which((object@niche_DE_pval_pos$gene_level<(alpha)) &
                         (object@niche_DE_pval_pos$cell_type_level[,ct_index]<(alpha)) &
                         (object@niche_DE_pval_pos$interaction_level[ct_index,niche_index,]<(alpha/2)))
    genes = object@gene_names[gene_index]
    #get associated pvalues
    pval = object@niche_DE_pval_pos$interaction_level[ct_index,niche_index,gene_index]
    #save results
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Interaction')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }
  if(test.level=='interaction' & direction=='negative'){
    ct_index = which(colnames(object@num_cells)==index)
    niche_index = which(colnames(object@num_cells)==niche)
    gene_index = which((object@niche_DE_pval_neg$gene_level<(alpha)) &
                         (object@niche_DE_pval_neg$cell_type_level[,ct_index]<(alpha)) &
                         (object@niche_DE_pval_neg$interaction_level[ct_index,niche_index,]<(alpha/2)))
    genes = object@gene_names[gene_index]
    #get associated pvalues
    pval = object@niche_DE_pval_neg$interaction_level[ct_index,niche_index,gene_index]
    #save results
    result = data.frame(genes,pval)
    colnames(result) = c('Genes','Pvalues.Interaction')
    rownames(result) = c(1:nrow(result))
    print('Returning Niche-DE Genes')
    result = result[order(result[,2]),]
    return(result)
  }
}

#' Get Niche-DE marker genes
#'
#' This function returns genes marker genes in the index cell type when near the first niche cell type realtive to the second one
#'
#' @param object A niche-DE object
#' @param index The index cell type which we want to find marker genes for
#' @param niche1 The niche cell type for the marker genes found
#' @param niche2 The niche we wish to compare (index,niche1) patterns to
#' @param pos Logical indicating whether to return genes that are (index,niche)+
#' patterns (pos = T) or (index,niche)- (pos = F)
#' @param alpha The level at which to perform the Benjamini Hochberg correction. Default value is 0.05.
#' @return A vector of genes that are niche marker genes for the index cell type
#'  near the niche1 cell type relative to the niche2 cell type
#' @export
niche_DE_markers = function(object,index,niche1,niche2,alpha = 0.05){


  if((index %in% colnames(object@num_cells))==F){
    stop('Index cell type not found')
  }
  if((niche1 %in% colnames(object@num_cells))==F){
    stop('Niche1 cell type not found')
  }
  if((niche2 %in% colnames(object@num_cells))==F){
    stop('Niche2 cell type not found')
  }

  print(paste0('Finding Niche-DE marker genes in index cell type ',index,' with niche cell type ',niche1,
               ' relative to niche cell type ',niche2,'. BH procedure performed at level ',alpha,'.'))

  #get beta array
  betas_all = object@niche_DE[[1]]$beta
  #get variance covariance array
  v_cov_all = object@niche_DE[[1]]$var_cov
  #get index for index and niche cell types
  index_index = which(colnames(object@num_cells)==index)
  niche1_index = which(colnames(object@num_cells)==niche1)
  niche2_index = which(colnames(object@num_cells)==niche2)

  #make sure that collocalization occurs
  #check to see if they have enough overlap
  colloc = check_colloc(object,index_index,niche1_index)
  for(value in c(1:length(colloc))){
    if(colloc[value]<30){
      warning('Less than 30 observations containing collocalization of ',index,
              ' and ',niche1,' at kernel bandwidth ',names(colloc)[value],
              '. Results may be unreliable.')
    }
  }

  #make sure that collocalization occurs
  #check to see if they have enough overlap
  colloc = check_colloc(object,index_index,niche2_index)
  for(value in c(1:length(colloc))){
    if(colloc[value]<30){
      warning('Less than 30 observations containing collocalization of ',index,
              ' and ',niche2,' at kernel bandwidth ',names(colloc)[value],
              '. Results may be unreliable.')
    }
  }




  #get marker pvals
  pval = contrast_post(betas_all,v_cov_all,index_index,c(niche1_index,niche2_index))
  #if multiple kernels do this for all kernels
  if(length(object@sigma)>=2){
    for(j in c(2:length(object@sigma))){
      #print(j)
      betas_all = object@niche_DE[[j]]$beta
      v_cov_all = object@niche_DE[[j]]$var_cov
      index_index = which(colnames(object@num_cells)==index)
      niche1_index = which(colnames(object@num_cells)==niche1)
      niche2_index = which(colnames(object@num_cells)==niche2)
      pval = cbind(pval,contrast_post(betas_all,v_cov_all,index_index,c(niche1_index,niche2_index)))
    }
  }
  #apply cauchy combination
  #record log likelihoods
  log_liks = object@niche_DE[[1]]$log_lik
  if(length(object@niche_DE)>=2){
    for(j in c(2:length(object@niche_DE))){
      log_liks = cbind(log_liks,object@niche_DE[[j]]$log_lik)
    }
  }
  if(length(object@niche_DE)>=2){
    log_liks[is.infinite(log_liks)] = 0
    suppressWarnings({ W = t(apply(log_liks,1,function(x){exp(x-min(x,na.rm = T))}))})
  }

  if(length(object@niche_DE)==1){
    log_liks[is.infinite(log_liks)] = 0
    suppressWarnings({ W = rep(1,length(log_liks))})
  }

  #W = apply(W,1,function(x){x/sum(x)})
  W[is.infinite(W)] = 10e160
  #bind pvalues and weights
  contrast = cbind(pval,W)
  #apply cauchy rule
  contrast = as.matrix(apply(contrast,1,function(x){gene_level(x[1:(length(x)/2)],x[(length(x)/2+1):length(x)])}))
  #apply BH
  contrast_phoch = p.adjust(contrast,method = "BH")
  #bind genes and their pvalue
  gene_pval = data.frame(object@gene_names,contrast_phoch)
  #filter to only those that reject
  gene_pval = gene_pval[which(gene_pval[,2]<(alpha/2)),]
  colnames(gene_pval) = c('Genes','Adj.Pvalues')
  rownames(gene_pval) = c(1:nrow(gene_pval))
  print('Marker gene analysis complete.')
  gene_pval = gene_pval[order(gene_pval[,2]),]
  return(gene_pval)

}


#' Perform Niche-LR (Ligand receptor analysis) on spot level data
#'
#' This function returns ligands and receptors inferred to be expressed by the given cell types
#'
#' @param object A niche-DE object
#' @param ligand_cell The cell type that expresses the ligand
#' @param receptor_cell The cell type that expresses the receptor
#' @param ligand_target_matrix A matrix that measures the association between
#' ligands and their downstream target genes. Should be target genes by ligands
#' @param lr_mat A matrix that matches ligands with their corresponding receptors.
#' This matrix should have two columns. The first will be ligands and the second
#' will be the corresponding receptors
#' @param K The number of downstream target genes to use when calculating the
#' ligand potential score. Default value is 25.
#' @param M The maximum number of ligands that can pass initial filtering. Default value is 50.
#' @param alpha The level at which to perform the Benjamini Hochberg correction. Default value is 0.05.
#' @param truncation_value The value at which to truncate T statistics. Default value is 3.
#' @return A list of ligand-receptor pairs that are found to be expressed by the
#' specified cell type
#' @export
niche_LR_spot = function(object,ligand_cell,receptor_cell,ligand_target_matrix,lr_mat,K = 25,M = 50,alpha = 0.05,truncation_value = 3){
  #The ligand expressing cell should be the niche cell
  niche = which(colnames(object@num_cells)==ligand_cell)
  #The receptor expressing cell should be the index cell
  index = which(colnames(object@num_cells)==receptor_cell)

  print(paste0('Performing niche-LR with hyperparameters K = ',K,', M = ',M,', alpha = ',alpha,
               ', truncation value = ',truncation_value,'.'))
  print(paste0('Finding ligand receptors between ligand expressing cell type ',ligand_cell,
               ' and receptor expressing cell type ',receptor_cell,'.'))
  #make sure that collocalization occurs
  #check to see if they have enough overlap
  colloc = check_colloc(object,index,niche)
  for(value in c(1:length(colloc))){
    if(colloc[value]<30){
      warning('Less than 30 observations containing collocalization of ',receptor_cell,
              ' and ',ligand_cell,' at kernel bandwidth ',names(colloc)[value],
              '. Results may be unreliable.')
    }
  }


  log_liks = object@niche_DE[[1]]$log_lik
  if(length(object@niche_DE)>=2){
    for(j in c(2:length(object@niche_DE))){
      log_liks = cbind(log_liks,object@niche_DE[[j]]$log_lik)
    }
  }

  if(length(object@niche_DE)>=2){
    #get best kernel for each gene
    top_kernel = apply(log_liks,1,function(x){order(x,decreasing = T)[1]})
  }

  if(length(object@niche_DE)==1){
    #get best kernel for each gene
    top_kernel = rep(1,length(log_liks))
  }

  #get T_statistic list
  T_vector = vector(mode = "list", length = length(object@sigma))
  for(j in c(1:length(object@sigma))){
    T_vector[[j]] = object@niche_DE[[j]]$T_stat[index,niche,]
  }
  #truncate niche_DE t-statistic
  for(j in c(1:length(T_vector))){
    T_vector[[j]] = pmin(T_vector[[j]],abs(truncation_value))
    T_vector[[j]] = pmax(T_vector[[j]],-abs(truncation_value))
  }
  #get library reference
  L = object@ref_expr
  #get cutoffs to consider a ligand for each cell type
  CT_filter = apply(L,1,function(x){quantile(x,0.25)})
  #filter ligands
  cand_lig = colnames(L)[which(L[niche,]>CT_filter[niche])]
  filter = which(colnames(ligand_target_matrix)%in% cand_lig)
  ligand_target_matrix = ligand_target_matrix[,filter]

  print('Calculating ligand potential scores')
  #get ligand potential scores
  pear_cor = rep(NA,ncol(ligand_target_matrix))
  score_norm = rep(NA,ncol(ligand_target_matrix))

  #save top niche-DE genes
  top_DE = vector(mode = "list", length = ncol(ligand_target_matrix))
  names(top_DE) = colnames(ligand_target_matrix)
  #iterate over potential ligands
  for(j in c(1:ncol(ligand_target_matrix))){
    ligand = colnames(ligand_target_matrix)[j]
    if(ligand%in% colnames(L)){
      #get which index we need to query for best kernel
      ind = which(colnames(L)==ligand)
      #get best index
      top_index = top_kernel[ind]
      #get scores
      sig = T_vector[[top_index]]
      genes = object@gene_names
      filter = which(is.na(sig)==F)
      genes = genes[filter]
      sig = sig[filter]
      #get ligand_potential scores by summing up T_statistics weighted by scaled niche-net scores
      ligand_vec = ligand_target_matrix
      #filter to only include genes found in data
      filter = which(rownames(ligand_vec)%in% genes)
      #filter
      ligand_vec = ligand_vec[filter,]
      filter = which(genes%in%rownames(ligand_vec))
      sig = sig[filter]
      genes = genes[filter]
      ligand_vec = ligand_vec[genes,]
      ligand_vec[,j] = scale(ligand_vec[,j])
      #get top K downstream genes
      top_cors = order(ligand_vec[,j],decreasing = T)[1:K]
      #get weights based on scaled niche-net scores
      weight = ligand_vec[top_cors,j]/mean(ligand_vec[top_cors,j])
      ##calculate ligand potential scores
      pear_cor[j] = sum(sig[top_cors]*weight)
      top_DE[[j]] = paste((rownames(ligand_vec)[top_cors])[order(sig[top_cors]*weight,decreasing = T)[1:5]],collapse = ',')
      #get normalizing constant
      score_norm[j] = sum(weight^2)
    }
  }
  #get scaled ligand-potential scores
  pear_cor = pear_cor/sqrt(score_norm)
  #get top candidate ligands
  top_index = which(pear_cor>=max(1.64,sort(pear_cor,decreasing = T)[M]))
  top_scores= pear_cor[top_index]
  #get top candidate ligands
  top_genes = colnames(ligand_target_matrix)[top_index]
  if(length(top_genes)==0){
    stop('No candidate ligands')
  }
  #################### test candidate ligands
  print(paste0('Testing candidate ligands for sufficient expression in cell type ',ligand_cell))
  pvalues = c()
  beta = c()
  for(j in c(1:length(top_genes))){
    tryCatch({
      #get candidate ligand
      gene = top_genes[j]
      #get what index it belongs to
      index_gene = which(colnames(L)==gene)
      #get best kernel
      top_index = top_kernel[index_gene]
      #get counts data for that gene
      data = object@counts
      Y = (data[,which(colnames(L)==gene)])
      #which spots to look at
      #niche_index = which(kernel_materials[[top_index]]$EN[,index]>0)
      niche_index = which(object@effective_niche[[top_index]][,index]>min(object@effective_niche[[top_index]][,index]))
      #filter data to only look at these spots
      Y = Y[niche_index]
      #get number of cells per spot
      nst = object@num_cells
      nst = nst[niche_index,]
      nst[,which(L[,index_gene] < CT_filter)] = 0
      #run regression of ligand expression on number of cells per spot
      if(L[niche,index_gene] < CT_filter[niche]){
        beta = c(beta,NA)
        pvalues = c(pvalues,NA)
      }else{
        check = suppressWarnings({glm(Y~nst,family = 'poisson')})
        bad_ind = which(is.na(coef(check)))
        num_bad = sum(bad_ind<(niche+1))
        beta = c(beta,coef(check)[niche+1])
        pvalues = c(pvalues,summary(check)$coefficients[(niche+1-num_bad),4])
      }

    } #get pval
    , error = function(e) {
      skip_to_next <<- TRUE})
  }
  #adjust pvalues and get confirmed ligands
  pvalues = p.adjust(pvalues,method = 'BH')
  ligands = top_genes[which(pvalues<alpha &beta>0)]

  #get candidate receptor
  rec_ind = which(lr_mat[,1]%in% ligands & lr_mat[,2]%in% colnames(L))
  lr_mat = lr_mat[rec_ind,]
  receptors = lr_mat[,2]
  #run regression to see if receptor is expressed by index cell type
  pvalues = c()
  beta = c()
  gene_name = c()
  #iterate over all receptors
  print(paste0('Testing candidate receptors for sufficient expression in cell type ',receptor_cell))
  for(j in c(1:length(receptors))){
    tryCatch({
      #get receptor
      gene = receptors[j]
      #get corresponding ligand
      lig = lr_mat[j,1]
      #get index for the ligand and the optimal kernel
      index_lig = which(colnames(L)==lig)
      top_index = top_kernel[index_lig]
      #get data
      data = object@counts
      Y = data[,which(colnames(L)==gene)]
      #which spots to look at
      #niche_index = which(kernel_materials[[top_index]]$EN[,niche]>0)
      niche_index = which(object@effective_niche[[top_index]][,niche]>min(object@effective_niche[[top_index]][,niche]))
      #filter based on spots to look at
      Y = Y[niche_index]
      nst = object@num_cells[niche_index,]
      nst[,which(L[,index_lig] < CT_filter)] = 0
      #run regression
      if(L[index,index_lig] < CT_filter[index]){
        beta = c(beta,NA)
        pvalues = c(pvalues,NA)
      }else{
        check = suppressWarnings({glm(Y~nst,family = 'poisson')})
        bad_ind = which(is.na(coef(check)))
        num_bad = sum(bad_ind<(index+1))
        beta = c(beta,coef(check)[index+1])
        pvalues = c(pvalues,summary(check)$coefficients[(index+1-num_bad),4])
      }
    }
    , error = function(e) {
      print(paste0("error",j))
      skip_to_next <<- TRUE})
  }
  #adjust pvalues
  pvalues = p.adjust(pvalues,method = "BH")
  rec_mat = cbind(lr_mat,beta,pvalues)
  #look at those with postive beta values
  rec_mat = rec_mat[as.numeric(rec_mat[,3])>0,]
  #name matrix columns
  colnames(rec_mat) = c('ligand','receptor','receptor_beta','receptor_pval')
  LR_pairs = rec_mat[,c(1,2,4)]
  #extract the confirmed ligands and receptors
  if(length(LR_pairs)==0){
    stop('no ligand-receptor pairs to report')
  }
  LR_pairs = LR_pairs[which(as.numeric(LR_pairs[,3])<alpha),c(1:3)]
  for(j in unique(LR_pairs[,1])){
    #get gene/ligand name
    #match to top_DE list
    ID = which(names(top_DE)==j)
    print(ID)
    #get downstream genes
    LR_pairs[which(LR_pairs[,1]==j),3] = top_DE[[ID]]
  }

  colnames(LR_pairs) = c('ligand','receptor','top_downstream_niche_DE_genes')
  rownames(LR_pairs) = c(1:nrow(LR_pairs))

  print(paste0('Returning ligand receptor table between ligand expressing cell type ',ligand_cell,
               ' and receptor expressing cell type ',receptor_cell,'.'))
  return(LR_pairs)

}

#' Perform Niche-LR (Ligand receptor analysis) on single cell level data
#'
#' This function returns ligands and receptors inferred to be expressed by the given cell types
#'
#' @param object A niche-DE object
#' @param ligand_cell The cell type that expresses the ligand
#' @param receptor_cell The cell type that expresses the receptor
#' @param ligand_target_matrix A matrix that measures the assocaition between
#' ligands and their downstream target genes. Should be target genes by ligands
#' @param lr_mat A matrix that matches ligands with their corresponding receptors.
#' This matrix should have two columns. The first will be ligands and the second
#' will be the corresponding receptors
#' @param K The number of downstream target genes to use when calculating the
#' ligand potential score. Default value is 25.
#' @param M The maximum number of ligands that can pass initial filtering. Default value is 50.
#' @param alpha The level at which to perform the Benjamini Hochberg correction. Default value is 0.05.
#' @param alpha_2 The null quantile to compare observed expression to. Default value is 0.5 (50th percentile).
#' @param truncation_value The value at which to truncate T statistics. Default value is 3.
#' @return A list of ligand-receptor pairs that are found to be expressed by the
#' specified cell type
#' @export
niche_LR_cell = function(object,ligand_cell,receptor_cell,ligand_target_matrix,
                         lr_mat,K = 25,M = 50,alpha = 0.05,alpha_2 = 0.5,truncation_value = 3){
  niche = which(colnames(object@num_cells)==ligand_cell)
  index = which(colnames(object@num_cells)==receptor_cell)
  print(paste0('Performing niche-LR with hyperparameters K = ',K,', M = ',M,', alpha = ',alpha,', alpha_2 = ',alpha_2,
               ', truncation value = ',truncation_value,'.'))
  print(paste0('Finding ligand receptors between ligand expressing cell type ',ligand_cell,
               ' and receptor expressing cell type ',receptor_cell,'.'))

  #make sure that collocalization occurs
  #check to see if they have enough overlap
  colloc = check_colloc(object,index,niche)
  for(value in c(1:length(colloc))){
    if(colloc[value]<30){
      warning('Less than 30 observations containing collocalization of ',receptor_cell,
              ' and ',ligand_cell,' at kernel bandwidth ',names(colloc)[value],
              '. Results may be unreliable.')
    }
  }


  log_liks = object@niche_DE[[1]]$log_lik
  if(length(object@niche_DE)>=2){
    for(j in c(2:length(object@niche_DE))){
      log_liks = cbind(log_liks,object@niche_DE[[j]]$log_lik)
    }
  }
  if(length(object@niche_DE)>=2){
    #get best kernel for each gene
    top_kernel = apply(log_liks,1,function(x){order(x,decreasing = T)[1]})
  }

  if(length(object@niche_DE)==1){
    #get best kernel for each gene
    top_kernel = rep(1,length(log_liks))
  }

  #get T_statistic list
  T_vector = vector(mode = "list", length = length(object@sigma))
  for(j in c(1:length(object@sigma))){
    T_vector[[j]] = object@niche_DE[[j]]$T_stat[index,niche,]
  }
  #truncate niche_DE t-statistic
  for(j in c(1:length(T_vector))){
    T_vector[[j]] = pmin(T_vector[[j]],abs(truncation_value))
    T_vector[[j]] = pmax(T_vector[[j]],-abs(truncation_value))
  }
  #get library reference
  L = object@ref_expr
  #get cutoffs to consider a ligand for each cell type
  CT_filter = apply(L,1,function(x){quantile(x,0.25)})
  #filter ligands
  cand_lig = colnames(L)[which(L[niche,]>CT_filter[niche])]
  filter = which(colnames(ligand_target_matrix)%in% cand_lig)
  ligand_target_matrix = ligand_target_matrix[,filter]

  print('Calculating ligand potential scores')
  #get ligand potential scores
  pear_cor = rep(NA,ncol(ligand_target_matrix))
  score_norm = rep(NA,ncol(ligand_target_matrix))

  #save top niche-DE genes
  top_DE = vector(mode = "list", length = ncol(ligand_target_matrix))
  names(top_DE) = colnames(ligand_target_matrix)

  #iterate over potential ligands
  for(j in c(1:ncol(ligand_target_matrix))){
    ligand = colnames(ligand_target_matrix)[j]
    if(ligand%in% colnames(L)){
      #get which index we need to query for best kernel
      ind = which(colnames(L)==ligand)
      #get best index
      top_index = top_kernel[ind]
      #get scores
      sig = T_vector[[top_index]]
      genes = object@gene_names
      filter = which(is.na(sig)==F)
      genes = genes[filter]
      sig = sig[filter]
      #get ligand_potential scores by summing up T_statistics weighted by scaled niche-net scores
      ligand_vec = ligand_target_matrix
      #filter to only include genes found in data
      filter = which(rownames(ligand_vec)%in% genes)
      #filter
      ligand_vec = ligand_vec[filter,]
      filter = which(genes%in%rownames(ligand_vec))
      sig = sig[filter]
      genes = genes[filter]
      ligand_vec = ligand_vec[genes,]
      ligand_vec[,j] = scale(ligand_vec[,j])
      #get top K downstreamm genes
      top_cors = order(ligand_vec[,j],decreasing = T)[1:K]
      #get weights based on scaled niche-net scors
      weight = ligand_vec[top_cors,j]/mean(ligand_vec[top_cors,j])
      ##calculate ligand potential scores
      pear_cor[j] = sum(sig[top_cors]*weight)
      #save top niche-DE genes of the ligand
      top_DE[[j]] = paste((rownames(ligand_vec)[top_cors])[order(sig[top_cors]*weight,decreasing = T)[1:5]],collapse = ',')
      #get normalizing constant
      score_norm[j] = sum(weight^2)
    }
  }
  #get scaled ligand-potential scores
  pear_cor = pear_cor/sqrt(score_norm)
  #get top candidate ligands
  top_index = which(pear_cor>=max(1.64,sort(pear_cor,decreasing = T)[M]))
  top_scores= pear_cor[top_index]
  #get top candidate ligands
  top_genes = colnames(ligand_target_matrix)[top_index]
  #print(top_genes)

  #################### test candidate ligands
  print(paste0('Testing candidate ligands for sufficient expression in cell type ',ligand_cell))
  pvalues = c()
  beta = c()
  for(j in c(1:length(top_genes))){
    tryCatch({
      #get candidate ligand
      gene = top_genes[j]
      #get what index it belongs to
      index_gene = which(colnames(L)==gene)
      #get best kernel
      top_index = top_kernel[index_gene]
      #get counts data for that gene
      data = object@counts
      Y = (data[,which(colnames(L)==gene)])
      #which spots to look at
      #niche_index = which(kernel_materials[[top_index]]$EN[,index]>0)
      niche_index = which(object@effective_niche[[top_index]][,index]>min(object@effective_niche[[top_index]][,index]))
      #filter data to only look at these spots
      Y = Y[niche_index]
      #get number of cells per spot
      nst = object@num_cells
      nst = nst[niche_index,]
      #print(dim(nst))
      nst[,which(L[,index_gene] < CT_filter)] = 0
      #run regression of ligand expression on number of cells per spot
      #get average expression of ligand
      lambda_niche = mean(Y[nst[,niche]==1])
      #print(niche)
      #print(lambda_niche)
      #get alpha quantile of niche cell type
      lambda_rest = quantile(object@ref_expr[niche,],alpha_2)
      #print(lambda_rest)
      #get test statistic
      Test_stat = lambda_niche-lambda_rest
      #normalize so that null distribution is standard normal
      Test_stat = Test_stat/sqrt(lambda_niche/sum(nst[,niche]==1))
      #append pvalues
      pvalues = c(pvalues,1-pnorm(Test_stat))

    } #get pval
    , error = function(e) {
      #print(paste0("error",j))
      skip_to_next <<- TRUE})
  }
  #adjust pvalues and get confirmed ligands
  pvalues = p.adjust(pvalues,method = 'BH')
  ligands = top_genes[which(pvalues<alpha)]
  #print(ligands)
  #get candidate receptor
  rec_ind = which(lr_mat[,1]%in% ligands & lr_mat[,2]%in% colnames(L))
  lr_mat = lr_mat[rec_ind,]
  receptors = lr_mat[,2]
  #run regression to see if receptor is expressed by index cell type
  pvalues = c()
  beta = c()
  gene_name = c()
  #iterate over all receptors
  print(paste0('Testing candidate receptors for sufficient expression in cell type ',receptor_cell))
  for(j in c(1:length(receptors))){
    tryCatch({
      #get receptor
      gene = receptors[j]
      #get corresponding ligand
      lig = lr_mat[j,1]
      #get index for the ligand and the optimal kernel
      index_lig = which(colnames(L)==lig)
      top_index = top_kernel[index_lig]
      #get data
      data = object@counts
      Y = data[,which(colnames(L)==gene)]
      #which spots to look at
      #niche_index = which(kernel_materials[[top_index]]$EN[,niche]>0)
      niche_index = which(object@effective_niche[[top_index]][,niche]>min(object@effective_niche[[top_index]][,niche]))
      #filter based on spots to look at
      Y = Y[niche_index]
      #get number of cells per spot
      nst = object@num_cells
      nst = nst[niche_index,]
      nst[,which(L[,index_lig] < CT_filter)] = 0
      #run regression
      lambda_niche = mean(Y[nst[,index]==1])
      lambda_rest = quantile(object@ref_expr[index,],alpha_2)
      Test_stat = lambda_niche-lambda_rest
      Test_stat = Test_stat/sqrt(lambda_niche/sum(nst[,index]==1))
      pvalues = c(pvalues,1-pnorm(Test_stat))
    }
    , error = function(e) {
      print(paste0("error",j))
      skip_to_next <<- TRUE})
  }
  #adjust pvalues
  pvalues = p.adjust(pvalues,method = "BH")
  #print(pvalues)
  rec_mat = cbind(lr_mat,pvalues)
  #name matrix columns
  colnames(rec_mat) = c('ligand','receptor','receptor_pval')
  LR_pairs = rec_mat[,c(1,2,3)]
  #print(dim(LR_pairs))
  #extract the confirmed ligands and receptors
  if(length(LR_pairs)==0){
    stop('no ligand-receptor pairs to report')
  }
  LR_pairs = LR_pairs[which(as.numeric(LR_pairs[,3])<alpha),c(1:3)]
  for(j in unique(LR_pairs[,1])){
    #match to top_DE list
    ID = which(names(top_DE)==j)
    #get downstream genes
    LR_pairs[which(LR_pairs[,1]==j),3] = top_DE[[ID]]
  }

  colnames(LR_pairs) = c('ligand','receptor','top_downstream_niche_DE_genes')
  rownames(LR_pairs) = c(1:nrow(LR_pairs))
  print(paste0('Returning ligand receptor table between ligand expressing cell type ',ligand_cell,
               ' and receptor expressing cell type ',receptor_cell,'.'))

  return(LR_pairs)

}

