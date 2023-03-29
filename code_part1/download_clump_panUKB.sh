#PBS -N download_clump_panUKB
#PBS -l nodes=1:ppn=1
#PBS -l pmem=16gb
#PBS -l walltime=48:00:00
#PBS -A GT-jlachance6
#PBS -q inferno
#PBS -j oe
#PBS -o download_clump_panUKB.out

# 2 - download_clump_panUKB.sh

# Bash script that extracts panUKB GWAS summary statistics for each trait, uses
# PLINK to LD prune for independent GWAS hits, and saves the file using the
# Rscript in filter_GWAS_independent.R.

### Directories and paths ###

# sets working directory
cd $PBS_O_WORKDIR
# sets directory to plink 1.9
dir_plink="~/plink1_9"
# sets path to 1000 Genomes binary files (or another prefered LD panel, preferably
# composed of just Europeans). Leave as just the prefix before the chromosome
# number and the file extensions
dir_1kG='/storage/home/hcoda1/1/ncarvalho6/scratch/12-19_1000G_phase3/'
loc_bfile=${dir_1kG}'phase3kG'
# sets path to text file containing FID and IID of individuals to use in LD panel
loc_LD_IIDs='/storage/home/hcoda1/1/ncarvalho6/scratch/12-19_1000G_phase3/EUR_IDs.txt'

# sets directory where panUKB GWAS summary statistics will be saved
dir_sf='../generated_data/panUKB_sf/'
# sets path to the traits_list.txt file
loc_traits_list='../input_data/traits_list.txt'


module load r/4.2.1-tidy

# Reads traits_list and extracts phenotype name and AWS summary file link
IFS=$'\n'
phenotypes=()
while read -r line; do phenotypes+=("$line"); done <<< "$(awk -F'\t' '(NR>1 && $21 == "TRUE") {print $1}' $loc_traits_list)"
aws_links=()
while read -r line; do aws_links+=("$line"); done <<< "$(awk -F'\t' '(NR>1 && $21 == "TRUE") {print $15}' $loc_traits_list)"

# Loops through each trait
length=${#phenotypes[@]}
for i in $(seq 0 $((length-1)))
do
phenotype=${phenotypes[$i]}
echo ========== [${i} ${phenotype}] ==========

# downloads large panUKB GWAS summary file (zipped, about 2.5GB)
echo [${i} ${phenotype}] Downloading panUKB summary file
aws_link=${aws_links[$i]}
wget -qO ${dir_sf}${phenotype}_raw_sf.tsv.bgz ${aws_link}

# unzips panUKB GWAS summary file
echo [${i} ${phenotype}] Unzipping summary file
zcat ${dir_sf}${phenotype}_raw_sf.tsv.bgz > ${dir_sf}${phenotype}_raw_sf.tsv
rm -v ${dir_sf}${phenotype}_raw_sf.tsv.bgz

# transforms summary file to allow PLINK to properly interact with it
echo [${i} ${phenotype}] Transforming summary file for PLINK
index=$(awk -F'\t' '{for (i=1; i<=NF; i++) if ($i == "pval_meta") print i; exit}' ${dir_sf}${phenotype}_raw_sf.tsv)
# if index is empty (no meta GWAS was done), it instead looks for pval_EUR
if [ -z "$index" ]; then index=$(awk -F'\t' '{for (i=1; i<=NF; i++) if ($i == "pval_EUR") print i; exit}' ${dir_sf}${phenotype}_raw_sf.tsv); fi

awk -F'\t' -v col="$index" '{if (NR == 1) {print "SNP\tpval\t"$0} else if ($col != "NA"){print $1":"$2"\t"exp($col)"\t"$0}}' ${dir_sf}${phenotype}_raw_sf.tsv > ${dir_sf}${phenotype}_sf.tsv

# runs --clump in PLINK to LD prune GWAS summary results
echo [${i} ${phenotype}] Running --clump in PLINK

pval_cutoff=0.0001
r2_cutoff=0.2

~/plink1_9/plink \
--bfile ${loc_bfile} \
--allow-extra-chr \
--keep ${loc_LD_IIDs} \
--clump ${dir_sf}${phenotype}_sf.tsv \
--clump-snp-field SNP \
--clump-field pval \
--clump-p1 ${pval_cutoff} \
--clump-r2 ${r2_cutoff} \
--out ${dir_sf}${phenotype}_sf

# runs Rscript to filter full summary statistics to just independent SNPs
echo [${i} ${phenotype}] Filtering GWAS summary file for independent SNPs
Rscript helper_functions/filter_GWAS_independent.R ${phenotype}

# removes all trait-specific files except for filtered GWAS summary statistics
rm -v ${dir_sf}${phenotype}_raw_sf.*
rm -v ${dir_sf}${phenotype}_sf.*

done

echo DONE WITH ALL TRAITS


####
# Make list of all unique SNPs in the above summary files
output_file="../generated_data/all_sf_SNPs.txt"

# Loop through each file in the directory
for file in "${dir_sf}"*.txt; do
  echo ${file}
  # Extract the chromosome and position columns and append to output file
  awk 'BEGIN {FS="\t"; OFS=" "} NR>1 {print $3, $4, $4, 1}' "${file}" >> "${output_file}"
done

# Remove duplicate rows from the output file
sort "${output_file}" | uniq > "${output_file}.tmp"
mv "${output_file}.tmp" "${output_file}"

####
# Groups 1kG samples by continent
loc_sample_info=${dir_1kG}'20130606_sample_info.txt'
loc_out=${dir_1kG}'1kG_continent_IDs.txt'

awk -F"\t" 'BEGIN{OFS=" "}
    NR>1 {
        if ($2=="ACB" || $2=="ASW" || $2=="ESN" || $2=="GWD" || $2=="LWK" || $2=="MSL" || $2=="YRI") {continent="AFR"}
        else if ($2=="BEB" || $2=="GIH" || $2=="ITU" || $2=="PJL" || $2=="STU") {continent="SAS"}
        else if ($2=="CDX" || $2=="CHB" || $2=="CHS" || $2=="JPT" || $2=="KHV") {continent="EAS"}
        else if ($2=="CEU" || $2=="FIN" || $2=="GBR" || $2=="IBS" || $2=="TSI") {continent="EUR"}
        else if ($2=="CLM" || $2=="MXL" || $2=="PEL" || $2=="PUR") {continent="AMR"}
        print $1, $1, continent
    }' ${loc_sample_info} > ${loc_out}
