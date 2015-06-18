## script to define eRNAs with the following features
# $pipeline_path/eRNA.define.sh $inputBG
################################################
# eRNA definition:
# 1) density higher than the basal level,  
# 2) summit >0.05 RPM, --> p<0.05 comparing to the transcriptional noise
# 3) located in non-generic regions (e.g. 500bp away from any annotated exons),
# 4) at least 100bp in length,
# 5) don't contain any splicing sites (donor or acceptor from trinity/cufflinks de novo assembly) 
# 6) q-value<0.05 in at least 25% samples when comparing with random non-functional background
################################################

pipeline_path=$HOME/neurogen/pipeline/RNAseq
source $pipeline_path/config.txt

cd ~/projects/PD/results/eRNA/externalData/RNAseq

inputBG=/data/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bedGraph


# ===========================================================================
#: background region to measure transcriptional noise: genomic regions excluding the known regions with RNA activities (known exons+/-500bp, rRNA, CAGE-defined enhancers, promoters)
# ===========================================================================

ANNOTATION=$GENOME/Annotation/Genes
cat $ANNOTATION/gencode.v19.annotation.bed12 $ANNOTATION/knownGene.bed12 $ANNOTATION/NONCODEv4u1_human_lncRNA.bed12 | bed12ToBed6 | cut -f1-3 | grep -v "_" | slopBed -g $GENOME/Sequence/WholeGenomeFasta/genome.fa.fai -b 500 > /tmp/bg.bed
cut -f1-3 $ANNOTATION/rRNA.bed >> /tmp/bg.bed  # rRNA
# +/-500bp flanking around the CAGE-predicted TSS (downloaded from: http://fantom.gsc.riken.jp/5/datafiles/latest/extra/TSS_classifier/)
grep -v track ~/projects/PD/results/eRNA/externalData/CAGE/TSS_human.bed | grep -v "211,211,211" | cut -f1-3 | grep -v "_" | slopBed -g $GENOME/Sequence/WholeGenomeFasta/genome.fa.fai -b 500 >> /tmp/bg.bed 
#cat $ANNOTATION/SINE.bed $ANNOTATION/LINE.bed | cut -f1-3 >> /tmp/bg.bed  # LINE and SINE
cat $ANNOTATION/hg19.gap.bed >> /tmp/bg.bed  # genomic gap
cat /tmp/bg.bed | sortBed | mergeBed -i - > ../toExclude.bed
grep -v track ~/projects/PD/results/eRNA/externalData/CAGE/permissive_enhancers.bed | cut -f1-3 >> /tmp/bg.bed # CAGE-enhancer
cat /tmp/bg.bed | sortBed | mergeBed -i - > ../blacklist.bed

# RNAseq signal distribution in the background region
intersectBed -a $inputBG -b ../blacklist.bed -sorted -v | awk '{OFS="\t"; print $3-$2, $4}' | shuf > transcriptional.noise.rpm.txt

#R
df=read.table("transcriptional.noise.rpm.txt", comment.char = "", nrows = 2000000)
df=log10(as.numeric(do.call('c',apply(df, 1, function(x) rep(x[2],x[1])))))
library(fitdistrplus)
fitn=fitdist(df,'norm')
pdf("transcriptional.noise.distribution.pdf", width=8, height=6)
hist(df, breaks=100, prob=TRUE, xlab='log10(RPM)', main='Distribution of transcriptional noise')
lines(density(df, bw=0.15))
m=round(as.numeric(fitn$estimate[1]),digits=3)
sd=round(as.numeric(fitn$estimate[2]),digits=3)
lines(density(rnorm(n=2000000, mean=m, sd=sd),bw=0.25), col='blue',lty=2)
p=round(qnorm(.05, mean=m, sd=sd, lower.tail = F), digits=3)
lines(y=c(0,0.3),x=c(p,p),col='red')
text(p,0.2,paste0("P(X>",p,") = 0.05\nRPM=10**",p,"=",round(10**p,digits=3)), adj=c(0,0))
legend("topright", c("empirical density curve", paste0("fitted normal distribution \n(mean=",m,", sd=",sd,")")), col=c('black','blue'), lty=c(1,2), bty='n')
dev.off()

# Dsig: 10**-1.105 == 0.079

## any region with RPM density > 0.101
#basalLevel=0.101
#j=`basename ${inputBG/bedGraph/eRNA.bed}`
#awk -vmin=$basalLevel '{OFS="\t"; if($4>min) print $1,$2,$3,".",$4}' $inputBG | mergeBed -d 100 -scores max | intersectBed -a - -b ../toExclude.bed -v > $j
##wc -l $j
##40451 trimmedmean.uniq.normalized.HCILB_SNDA.eRNA.bed

#for i in /data/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bedGraph;
#do
#    basalLevel=`tail -n1 $i | cut -f2 -d'=' | cut -f1 -d' '`
#    echo $i, $basalLevel;
#    j=`basename ${i/bedGraph/eRNA.bed}`
#    awk -vmin=$basalLevel '{OFS="\t"; if($4>=2*min) print $1,$2,$3,".",$4}' $i | mergeBed -scores max | awk '{OFS="\t"; if($4>=0.05) print $1,$2,$3,".",$4}' | mergeBed -d 100 -scores max | intersectBed -a - -b ../toExclude.bed -v > $j &
#done

# step1: any regions with summit RPM > peakLevel and border > baseLevel
# =================
basalLevel=`tail -n1 $inputBG | cut -f2 -d'=' | cut -f1`
awk -vmin=$basalLevel '{OFS="\t"; if($4>=min) print $1,$2,$3,".",$4}' $inputBG | mergeBed -scores max > eRNA.tmp1

# step2: summit RPM >=Dsig (density with p<0.05)
# =================
Dsig=0.079
awk -vD=$Dsig '{OFS="\t"; if($4>=D) print $1,$2,$3,".",$4}' eRNA.tmp1 | mergeBed -d 100 -scores max > eRNA.tmp2

# step3: located in non-generic regions (e.g. 500bp away from any annotated exons),
# =================
intersectBed -a eRNA.tmp2 -b ../toExclude.bed -v > eRNA.tmp3

# step4: length > 100nt
# =================
awk '{OFS="\t"; if(($3-$2)>100) print $1,$2,$3,$1"_"$2"_"$3}' eRNA.tmp3 > eRNA.tmp4

# step6: don't contain any splicing sites (donor or acceptor from trinity/cufflinks de novo assembly)
# =================
# cd ~/neurogen/rnaseq_PD/results/merged/denovo_assembly/
# cat cufflinks-cuffmerge/merged.bed trinity-cuffmerge/all_strand_spliced.chr.bed | awk '{OFS="\t";split($11,a,","); split($12,b,","); A=""; B=""; for(i=1;i<length(a)-1;i++) {A=A""(b[i+1]-b[i]-a[i])",";B=B""(b[i]+a[i]-(b[1]+a[1]))",";} if($10>1) print $1,$2+a[1], $3-a[length(a)-1], $4,$5,$6,$2+a[1], $3-a[length(a)-1],$9,$10-1,A,B;}' | bed12ToBed6 | awk '{OFS="\t"; print $1, $2-10,$2+10; print $1,$3-10,$3+10;}' | sortBed | uniq > trinitycufflinks.merged.splicingsites.flanking20nt.bed

# more than 10 splicing reads in at least 5 samples
# for i in  ~/neurogen/rnaseq_PD/run_output/*/junctions.bed; do awk '{OFS="\t"; if($5>10) { split($11,a,","); split($12,b,","); print $1,$2+a[1]-10,$2+a[1]+10; print $1,$2+b[2]-10,$2+b[2]+10}}' $i | sortBed | uniq; done | sort | uniq -c | awk '{OFS="\t"; if($1>5) print $2,$3,$4}' > ~/neurogen/rnaseq_PD/results/merged/denovo_assembly/tophatjunctions.merged.splicingsites.flanking20nt.bed
 
intersectBed -a eRNA.tmp4 -b ~/neurogen/rnaseq_PD/results/merged/denovo_assembly/tophatjunctions.merged.splicingsites.flanking20nt.bed -v > eRNA.tmp5

# step5: calculate the significance of eRNA
# =================
#1: create 100,000 random regions (400bp each) as background and calculate their signals
for i in ~/neurogen/rnaseq_PD/run_output/*/uniq/accepted_hits.normalized.bw ~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw;
do
    [ -e $i.rdbg ] || bsub -q normal -n 1 "bedtools shuffle -excl ../toExclude.bed -noOverlapping -i eRNA.tmp5 -g $GENOME/Annotation/Genes/ChromInfo.txt | bigWigAverageOverBed $i stdin stdout | cut -f1,5 > $i.rdbg";
    [ -e $i.eRNA.meanRPM ] || bsub -q normal -n 1 "bigWigAverageOverBed $i eRNA.tmp5 stdout | cut -f1,5 | sort -k1,1 > $i.eRNA.meanRPM"
done

### 2: distribution of random background, in order to define the cutoff with p=0.0001 significance
R
# significance
path=c("~/neurogen/rnaseq_PD/results/merged/trimmedmean.uniq.normalized.HCILB_SNDA.bw", "~/neurogen/rnaseq_PD/run_output/[HI]*_SNDA*rep[0-9]/uniq/accepted_hits.normalized.bw")

## read in only the 80 subjects/samples (w/ genotype)
IDs=read.table('~/neurogen/rnaseq_PD/results/merged/RNAseqID.wGenotyped.list',stringsAsFactors =F)[,1]
IDs=IDs[grep("^[HI].*_SNDA", IDs)]
EXP=data.frame(); PV=data.frame(); QV=data.frame(); id="locus"

pdf("background.RNAseq.cummulative.plot.pdf")
for(i in Sys.glob(path)){
    ii=ifelse(grepl("merged", i), sub(".*merged/(.*).bw.*","\\1", i), sub(".*run_output/(.*)/uniq.*","\\1", i));
    if(! (ii %in% IDs || grepl("trimmedmean",ii))) next;
    print(i)
    # read background
    df=read.table(paste(i,"rdbg",sep="."), header=F)[,2] # mean RPM (mean0 from bigWigAverageOverBed)
    Fn=ecdf(df)
    
    # plot the cummulative plot
    plot(Fn, verticals = TRUE, do.points = FALSE, main=ii, ylim=c(0.99, 1), xlab="average RPM", ylab="cummulative percentage (approx. 1-p)")
    inv_ecdf <- function(f){ x <- environment(f)$x; y <- environment(f)$y; approxfun(y, x)}; g <- inv_ecdf(Fn);
    abline(h=0.999, v=g(0.999), col='red', lty=2, lwd=1)
    points(g(0.999), 0.999, col='red', pch=19)
    text(g(0.999), 0.999, round(g(0.999),2), cex=5, adj=c(0,1))
    
    if(grepl("trimmedmean",ii)) next;
    id=c(id, ii)

    # read expression
    expression=read.table(paste(i,"eRNA.meanRPM",sep="."), header=F)
    pvalue=as.numeric(format(1-Fn(expression[,2]), digits=3));
    qvalue=as.numeric(format(p.adjust(pvalue, "BH"), digits=3));
    write.table(cbind(expression[,1:2], pvalue=pvalue, qvalue=qvalue), file=paste(i,"eRNA.meanRPM.significance",sep="."), quote=F, sep ="\t", col.names =F, row.names=F)
    
    # merge
    if(ncol(EXP)==0) { EXP=expression; expression[,2]=pvalue; PV=expression; expression[,2]=qvalue; QV=expression; }
    else {EXP=cbind(EXP, expression[,2]); PV=cbind(PV, pvalue); QV=cbind(QV, qvalue); }
}
dev.off()

colnames(EXP)=id; colnames(PV)=id; colnames(QV)=id;
rM=rowMeans(QV[,-1]<=0.05)
write.table(EXP[rM>0.25,], "eRNA.90samples.meanRPM.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(PV[rM>0.25,], "eRNA.90samples.pvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)
write.table(QV[rM>0.25,], "eRNA.90samples.qvalue.xls", col.names=T, row.names=F, sep="\t", quote=F)

pdf("eRNA.90samples.qvalue.hist.pdf", width=8, height=6)
h=hist(rM, breaks=80, xlim=c(0,1), main="",xlab=expression("Percentage of HC/ILB SNDA samples (out of 90) with q-value" <= "0.05"), ylab="Count of HiTNEs", freq=T)
abline(v=0.250, lty=2, col='red')
legend('topright', c(bquote(.(sum(rM>0.25)) ~ "HiTNEs"), expression("with q-value" <= "0.05"), "in at least 25% of samples"),  bty='n', text.col='red', cex=1.5)
dev.off()

q('no')
## R end

awk '{OFS="\t"; split($1,a,"_"); if($1~/^chr/) print a[1],a[2],a[3],$1}' eRNA.90samples.meanRPM.xls > eRNA.bed


## merge menaRPM for all samples
R
path="~/neurogen/rnaseq_PD/run_output/*/uniq/accepted_hits.normalized.bw"
EXP=data.frame(); id="locus"
for(i in Sys.glob(path)){
    ii=sub(".*run_output/(.*)/uniq.*","\\1", i);
    print(i)
    id=c(id, ii)
    expression=read.table(paste(i,"eRNA.meanRPM",sep="."), header=F)
    if(ncol(EXP)==0) {
      EXP=expression; 
    } else {EXP=cbind(EXP, expression[,2]);}
}
colnames(EXP)=id; 
write.table(EXP, "eRNA.140samples.meanRPM.xls", col.names=T, row.names=F, sep="\t", quote=F)