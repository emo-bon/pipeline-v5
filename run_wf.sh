#!/bin/bash

# default values #
SCRIPT_PATH=$(realpath "$0")
PIPELINE_DIR=$(dirname "${SCRIPT_PATH}")
MEMORY=10G
NUM_CORES=1
LIMIT_QUEUE=100
YML="${PIPELINE_DIR}/Installation/templates/default.yml"
DB_DIR="${PIPELINE_DIR}/ref-dbs/"

_usage() {
  echo "
Run MGnify pipeline.
Script arguments.
  Resources:
  -m                  Memory to use to with toil --defaultMemory. (optional, default ${MEMORY})
  -c                  Number of cpus to use with toil --defaultCores. (optional, default ${NUM_CORES})
  -l                  Limit number of jobs to schedule. (optional, default ${LIMIT_QUEUE})

  Pipeline parameters:
  -y                  template yml file. (optional, default ../templates/rna_prediction_template.yml})
  -f                  Forward reads fasta file path.
  -r                  Reverse reads fasta file path.
  -n                  Name of run and prefix to output files.
  -d                  Path to run directory.
  -s                  Run workflow using Singularity (docker is the by default container technology) ('true' or 'false')
"
}

while getopts :y:f:r:e:u:k:c:d:m:n:l:sph option; do
  case "${option}" in
  y) YML=${OPTARG} ;;
  f)
    echo "Presented paired-end forward path:"
    FORWARD_READS=${OPTARG}
    ;;
  r)
    REVERSE_READS=${OPTARG}
    printf "Presented paired-end reverse path: ${REVERSE_READS}\n"
    ;;
  e) ENA_RUN_ID=${OPTARG} ;;
  u) ENA_USERNAME=${OPTARG} ;;
  k) ENA_PASSWORD=${OPTARG} ;;
  c) NUM_CORES=${OPTARG} ;;
  d) RUN_DIR=${OPTARG} ;;
  m) MEMORY=${OPTARG} ;;
  n) NAME=${OPTARG} ;;
  l) LIMIT_QUEUE=${OPTARG} ;;
  s) SINGULARITY="--singularity" ;;
  p) PRIVATE_DATA="-p" ;;
  h)
    _usage
    exit 0
    ;;
  :)
   usage
   exit 1
   ;;
  \?)
    echo ""
    echo "Invalid option -${OPTARG}" >&2
    usage
    exit 1
    ;;
  esac
done

# ----------------------------- sanity check arguments ----------------------------- #

_check_mandatory() {
  # Check if the argument is empty or null
  # $1 variable
  # $2 name to show
  if [ -z "$1" ]; then
    echo "Error." >&2
    echo "Option ${2} is mandatory " >&2
    echo "type -h to get help"
    exit 1
  fi
}

_check_reads() {
  #check forward and reverse reads both present
  #check if single reads then no other readsgiven

  #  BASH SYNTAX: 
  # to check if a variable has value: 
  # [ -z "$var" ] && echo "Empty"

  if [ -z "$1" ] && [ -n "$2" ]; then
    echo "Error"
    echo "only reverse reads given, provide forward with -f"
    exit 1
  fi

  if [ -n "$1" ] && [ -z "$2" ]; then
    echo "Error"
    echo "only forward reads given, provide reverse with -r"
    exit 1
  fi

}

_check_mandatory "$NAME" "-n"
_check_mandatory "$RUN_DIR" "-d"
_check_reads "$FORWARD_READS" "$REVERSE_READS" 



# ----------------------------- environment & variables ----------------------------- #

# load required environments and packages before running

export TOIL_SLURM_ARGS="--array=1-${LIMIT_QUEUE}%20" #schedule 100 jobs 20 running at one time
export CWL="${PIPELINE_DIR}/workflows/gos_wf.cwl"

# work dir
export WORK_DIR=${RUN_DIR}/work-dir
export JOB_TOIL_FOLDER=${WORK_DIR}/job-store-wf
export TMPDIR=${RUN_DIR}/tmp

# result dir
export OUT_DIR=${RUN_DIR}
export LOG_DIR=${OUT_DIR}/log-dir/${NAME}
export OUT_DIR_FINAL=${OUT_DIR}/results/${NAME}
export PROV_DIR=${OUT_DIR}/prov 

mkdir -p "${LOG_DIR}" "${OUT_DIR_FINAL}" "${JOB_TOIL_FOLDER}" "${TMPDIR}" # "${PROV_DIR}"

export RENAMED_YML_TMP=${RUN_DIR}/"${NAME}"_temp.yml
export RENAMED_YML=${RUN_DIR}/"${NAME}".yml

# Get study id in case of ENA fetch tool
if [[ $ENA_RUN_ID != "" ]];
then 

  # Run cwl for the ENA fetch tool
  cp tools/fetch-tool/get_raw_data_run.cwl .

  printf "
  run_accession_number: ${ENA_RUN_ID}
  private_data: true
  ena_api_username: ${ENA_USERNAME}
  ena_api_password: ${ENA_PASSWORD}
  " > get_raw_data_run-test.yml

  cwl-runner ${SINGULARITY} --outdir ${OUT_DIR} --debug get_raw_data_run.cwl get_raw_data_run-test.yml
 
  rm get_raw_data_run.cwl
  rm get_raw_data_run-test.yml

  # Get the accession id of the corresponding study
  ENA_STUDY_ID=$(curl -X POST "https://www.ebi.ac.uk/ena/browser/api/xml?accessions="$ENA_RUN_ID"&expanded=true" \
                -H "accept: application/xml" | grep -A 1 "ENA-STUDY" | tail -1 | sed 's/.*<ID>// ; s/<\/ID>//')

  export PATH_ENA_RAW_DATA=${PIPELINE_DIR}/${OUT_DIR}/raw_data_from_ENA/${ENA_STUDY_ID}/raw/


fi


# ----------------------------- prepare yml file ----------------------------- #

echo "Writing yaml file"

# DO NOT leave spaces after "\" in the end of a line
python3 create_yml.py \
  -y "${YML}" \
  -o "${RENAMED_YML_TMP}" \
  -l "${PATH_ENA_RAW_DATA}" \
  -f "${PIPELINE_DIR}/${FORWARD_READS}" \
  -r "${PIPELINE_DIR}/${REVERSE_READS}" \
  -d "${DB_DIR}" \
  -e "${ENA_RUN_ID}"
  # -s "${ENA_STUDY_ID}" \
  # -k "${ENA_PASSWORD}" \
  # -u "${ENA_USERNAME}"

mv eosc-wf.yml ${RUN_DIR}/
cat ${RUN_DIR}/eosc-wf.yml ${RENAMED_YML_TMP} > ${RENAMED_YML}
rm ${RENAMED_YML_TMP}
rm ${RUN_DIR}/eosc-wf.yml


# ----------------------------- running pipeline ----------------------------- #

# IMPORTANT! 
# To work with slurm, add "--batchSystem slurm", "--disableChaining" and "--disableCaching" in the TOIL_PARMS object
TOIL_PARAMS+=(
  --singularity
  --preserve-entire-environment
  --batchSystem slurm
  --disableChaining
  # --provenance "${PROV_DIR}"
  --disableCaching
  --logFile "${LOG_DIR}/${NAME}.log"
  --jobStore "${JOB_TOIL_FOLDER}/${NAME}"
  --outdir "${OUT_DIR_FINAL}"
  --maxCores 20
  --defaultMemory "${MEMORY}"
  --defaultCores "${NUM_CORES}"
  --retryCount 2
  --logDebug
  "$CWL"
  "$RENAMED_YML"
)

# Toir parameters documentation 
# --disableChaining                Disables  chaining  of jobs (chaining uses one job's resource allocation for its successor job if possible).
# --preserve-entire-environment    Need to propagate the env vars for Singularity, etc., into the HPC jobs
# --disableProgress                Disables the progress bar shown when standard error is a terminal.
# --retryCount                     Number of times to retry a failing job before giving up and labeling job failed. default=1
# --disableCaching                 Disables caching in the file store. This flag must be set to use a batch  system that does not support caching such as Grid Engine, Parasol, LSF, or Slurm.


#  # COMMENT IN TO RUN THE TOIL VERSION
# echo "toil-cwl-runner" "${TOIL_PARAMS[@]}"
# toil-cwl-runner "${TOIL_PARAMS[@]}"

cwl-runner ${SINGULARITY} --outdir ${OUT_DIR} --debug ${CWL} ${RENAMED_YML}
