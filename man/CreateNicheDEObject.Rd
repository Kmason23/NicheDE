% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/niche_DE_object_creation.R
\name{CreateNicheDEObject}
\alias{CreateNicheDEObject}
\title{CreateNicheDEObject}
\usage{
CreateNicheDEObject(counts_mat, coordinate_mat, library_mat, deconv_mat, sigma)
}
\arguments{
\item{counts_mat}{Counts matrix. Dimension should be cells/spots by genes}

\item{coordinate_mat}{Coordinate matrix}

\item{library_mat}{Matrix indicating average expression profile for each cell type in the sample}

\item{deconv_mat}{Deconvolution or cell type assignment matrix of data}

\item{sigma}{List of kernel bandwidths to use in calculating the effective niche}
}
\value{
A niche-DE object
}
\description{
This function creates a niche-DE object
}
