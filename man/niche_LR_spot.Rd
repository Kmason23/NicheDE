% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/niche_DE_main_functions.R
\name{niche_LR_spot}
\alias{niche_LR_spot}
\title{Perform Niche-LR (Ligand receptor analysis) on spot level data}
\usage{
niche_LR_spot(
  object,
  ligand_cell,
  receptor_cell,
  ligand_target_matrix,
  lr_mat,
  K = 25,
  M = 50,
  alpha = 0.05,
  truncation_value = 3
)
}
\arguments{
\item{object}{A niche-DE object}

\item{ligand_cell}{The cell type that expresses the ligand}

\item{receptor_cell}{The cell type that expresses the receptor}

\item{ligand_target_matrix}{A matrix that measures the association between
ligands and their downstream target genes. Should be target genes by ligands}

\item{lr_mat}{A matrix that matches ligands with their corresponding receptors.
This matrix should have two columns. The first will be ligands and the second
will be the corresponding receptors}

\item{K}{The number of downstream target genes to use when calculating the
ligand potential score. Default value is 25.}

\item{M}{The maximum number of ligands that can pass initial filtering. Default value is 50.}

\item{alpha}{The level at which to perform the Benjamini Hochberg correction. Default value is 0.05.}

\item{truncation_value}{The value at which to truncate T statistics. Default value is 3.}
}
\value{
A list of ligand-receptor pairs that are found to be expressed by the
specified cell type
}
\description{
This function returns ligands and receptors inferred to be expressed by the given cell types
}
