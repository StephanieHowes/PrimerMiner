
evaluate_primer <- function(alignment_imp, primer_sequ, start, stop, forward = T, save=NULL, gap_NA=T, N_NA=T, mm_position="Position_v1", mm_type="Type_v1", adjacent=2, sequ_names=T){

# load defults or load csv


if(is.null(mm_position)){stop("Pleas supply a table indicating penalty scorres for the mismatch possitions. Please see https://github.com/VascoElbrecht/PrimerMiner/wiki/6-Primer-evaluation-(in-silico) for details")
stop()} else if(mm_position=="Position_v1"){pos <- read.csv(paste(system.file(package="PrimerMiner"), "/Position_v1.csv", sep=""), header=F)
message("Using the default penalty score table (Position_v1)")	
} else {pos <- read.csv(mm_position, header=F)
message(paste("Penalty are used from the following table: ", mm_position, sep=""))}



if(is.null(mm_type)){message("Mismatch types are ignored.")}
if(mm_type=="Type_v1"){
type <- read.csv(paste(system.file(package="PrimerMiner"), "/Type_v1.csv", sep=""))
message("Using the default missmatch type table (Type_v1)")} else {
type <- read.csv(mm_type)
message(paste("Mismatch types are considered using the table: ", mm_type, sep=""))
}


# nucleotide table
upac <- read.csv(text=c("ID,comment,A,T,C,G, comp
A,Adenine,1,0,0,0,T
C,Cytosine,0,0,1,0,G
G,Guanine,0,0,0,1,C
T,Thymine,0,1,0,0,A
R,A or G,0.5,0,0,0.5,Y
Y,C or T,0,0.5,0.5,0,R
S,G or C,0,0,0.5,0.5,S
W,A or T,0.5,0.5,0,0,W
K,G or T,0,0.5,0,0.5,M
M,A or C,0.5,0,0.5,0,K
B,C or G or T,0,0.3,0.3,0.3,V
D,A or G or T,0.3,0.3,0,0.3,H
H,A or C or T,0.3,0.3,0.3,0,D
V,A or C or G,0.3,0,0.3,0.3,B
N,any base,0.25,0.25,0.25,0.25,N
I,inosine,0.25,0.25,0.25,0.25,N
-,gap,0,0,0,0,-"), stringsAsFactors=F)

upac[upac==0.3] <- 1/3
upac.score <- upac[,3:6] > 0


# import alignment an make matrix
alignment1 <- read.fasta(alignment_imp, seqonly=T)
alignment1  <- toupper(alignment1)
alignment <- unlist(strsplit(alignment1, split=""))
alignment <- matrix(alignment, nrow=length(alignment1), ncol=nchar(alignment1[1]), byrow=T)


if(sequ_names){
all_sequ_names <- read.fasta(alignment_imp, seqonly=F)
all_sequ_names <- names(all_sequ_names)
}

# order start stop - in case it was written in the "wrong" order
temp <- sort(c(start, stop))
start <- temp[1]
stop <- temp[2]

if(stop+1 - start == nchar(primer_sequ)){ # check primer length
message(paste(primer_sequ, " is ", nchar(primer_sequ), "bp long and length matches the propposed region" ,sep=""))
} else {warning("WARNING: length of the given region does NOT match the primer length. The script will crash now!")}

primer <- strsplit(primer_sequ, "")[[1]] # spit primer into nuceleotides

# extract regoin where primer does bind
primer_region <- alignment[,start:stop]


if(!forward){ # make rev comp of alignment!
primer_region <- primer_region[,ncol(primer_region):1]
primer_region <- matrix(upac$comp[match(primer_region, upac$ID)], nrow=nrow(primer_region), ncol=ncol(primer_region), byrow=F)
}


primer_woble <- upac[match(primer, upac$ID), 3:6] # get wobble scores for priemr
row.names(primer_woble) <- 1:nrow(primer_woble)
primer_woble <- primer_woble>0 # T = base present in wobble
primer_woble <- data.frame(primer_woble)

scores <- NULL

if (length(alignment1)==1){primer_region <- rbind(primer_region, primer_region)
primer_region_1 <- TRUE} else {primer_region_1 <- FALSE}# duplicate row if only one sequence!



i <- 23
for(i in 1:length(primer)){


sequ <- upac[match(primer_region[,i], upac$ID), 3:6]
sequ <- sequ>0
sequ <- data.frame(sequ) # determine what bases are present in sequ

woble <- rowSums(sequ) # wobles in sequ

sequ[,1] <- sequ[,1]-unlist(primer_woble[i,])[1]*2
sequ[,2] <- sequ[,2]-unlist(primer_woble[i,])[2]*2
sequ[,3] <- sequ[,3]-unlist(primer_woble[i,])[3]*2
sequ[,4] <- sequ[,4]-unlist(primer_woble[i,])[4]*2

error <- which(!rowSums(sequ==-1)>0) # sequences that do not match the primer woble
numberofmatches <- rowSums(sequ==-1)
match <- rep(0, nrow(sequ)) # 


sequ2 <- sequ
sequ2[sequ2==-2] <- 0 # remove -2 (= not a match)
sequ2[sequ2==-1] <- 1



wob_sequ_adj_factor <- (rowSums(sequ2)-numberofmatches)/rowSums(sequ2)
wob_sequ_adj_factor[error] <- 1
#wob_sequ_adj_factor[is.na(wob_sequ_adj_factor)] <- 1
wob_sequ_adj_factor <- as.vector(wob_sequ_adj_factor) # adjust for wobbles in sequence

match[error] <- pos[length(primer)+1-i,2]
match[wob_sequ_adj_factor<1] <- pos[length(primer)+1-i,2]


#cbind(primer_region[,i], "matches"=numberofmatches, "sequbase"=rowSums(sequ2), match, numberofmatches-rowSums(sequ2))



# adjustment of mismatch type
if(!is.null(mm_type)){

sequ3 <- sequ2
sequ3[,unlist(primer_woble[i,])] <- 0 # keep missmatches

# switch out bases, build rev comp! primer binds on complementary bases : )
sequ3 <- sequ3[c(2,1,4,3)]
names(sequ3) <- names(sequ2)


mm <- unlist(primer_woble[i,]) # bases present in primer

#type <- read.csv(mm_type) # mm table



type_scoes <- rep(NA, nrow(sequ3)) # empty table
for (m in c(1:4)[mm]){ # cycle trough bases present in primer

type_temp <- 0 # calculate scores for individual mm of primer base in sequ
for(n in 2:5){ # acount for wobbles in sequence
type_temp <- cbind(type_temp, sequ3[n-1]*type[m,n])
}
type_temp[type_temp==0] <- NA
factor <- rowSums(!is.na(type_temp), na.rm=T) # count number of nucleotides (wobles) in sequ
factor <- 1/factor
factor[is.infinite(factor)] <- NA
type_temp2 <- type_temp*factor
type_temp2 <- rowSums(type_temp2, na.rm=T)

type_scoes <- cbind(type_scoes, type_temp2)
}

type_scoes <- cbind(type_scoes, NA)

factor <- rowSums(!is.na(type_scoes), na.rm=T)
factor <- 1/factor
factor[is.infinite(factor)] <- NA
type_scoes2 <- type_scoes*factor
type_scoes2 <- rowSums(type_scoes2, na.rm=T)

type_scoes2[type_scoes2==0] <- 1

#type_scoes3 <- type_scoes2 * wob_sequ_adj_factor # adjust for woble bases that match the primer partially # already included

#cbind(primer_region[,i], "matches"=numberofmatches, "sequbase"=rowSums(sequ2), match, numberofmatches-rowSums(sequ2), type_scoes3, wob_sequ_adj_factor)

match <- match* type_scoes2
}

# cbind(primer_region[,24], type_scoes, wob_sequ_adj_factor)
# end mismatch type


if(gap_NA){match[primer_region[,i]=="-"] <- NA} else {match[primer_region[,i]=="-"] <- pos[length(primer)+1-i,2]}# mark gaps
if(N_NA){match[primer_region[,i]=="N"] <- NA} else {match[primer_region[,i]=="-"] <- pos[length(primer)+1-i,2]} # mark N s as NAs

match <- round(match* wob_sequ_adj_factor, digits=2)

scores <- cbind(scores, match)

}

# calculate increased error score for adjacent bases, factor has to be biger than 1!
if(adjacent>1){ 

for (i in 1:(ncol(scores)-1)){
adjTT <- paste(scores[,i]>0, scores[,(i+1)]>0)=="TRUE TRUE" # find adjacent values
scores[,i][adjTT] <- scores[,i][adjTT]* adjacent
scores[,(i+1)][adjTT] <- scores[,(i+1)][adjTT]* adjacent
}

}



scores <- data.frame(scores)
names(scores) <- paste("V", length(primer):1, sep="")

exp <- 1:nrow(primer_region) # save revcomp of primer region
for(k in 1:nrow(primer_region)){
exp[k] <- paste(primer_region[k,], collapse="")
}

scores <- data.frame("sequ"= exp, scores, "sum"=rowSums(scores))
row.names(scores) <- 1:nrow(scores)



if(primer_region_1){scores <- scores[1,]}# remove duplicated row, as only one sequence

if(sequ_names){
scores <- data.frame("Template"= all_sequ_names, scores)
}


if(!is.null(save)){write.csv(scores, save)} else {return(scores)}# save

message("I'm done = )")

}


#prompt(evaluate_primer, "evaluate_primer.Rd")

