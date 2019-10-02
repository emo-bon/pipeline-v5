#!/usr/bin/env cwl-runner

cwlVersion: v1.0
class: Workflow
label: "Amplicon and ITS Workflow"

requirements:
  SubworkflowFeatureRequirement: {}
  MultipleInputFeatureRequirement: {}
  InlineJavascriptRequirement: {}
  StepInputExpressionRequirement: {}
  ScatterFeatureRequirement: {}
#  SchemaDefRequirement:
#    types:
#      - $import: ../tools/biom-convert/biom-convert-table.yaml

inputs:
  qc_stats_summary: File
  query_sequences: File
  LSU_coordinates: File
  SSU_coordinates: File
  unite_database: {type: File, secondaryFiles: [.mscluster] }
  unite_taxonomy: File
  unite_otus: File
  itsone_database: {type: File, secondaryFiles: [.mscluster] }
  itsone_taxonomy: File
  itsone_otus: File
  otu_unite_label: string
  otu_itsone_label: string

outputs:

  masked_sequences:
    type: File
    outputSource: mask_for_ITS/masked_sequences

  unite_classifications:
    type: File
    outputSource: run_unite/mapseq_classifications

  unite_otu_tsv:
    type: File
    outputSource: run_unite/krona_tsv

  unite_otu_txt:
    type: File
    outputSource: run_unite/krona_txt

  unite_krona_image:
    type: File
    outputSource: run_unite/krona_image

  itsonedb_classifications:
    type: File
    outputSource: run_itsonedb/mapseq_classifications

  itsonedb_otu_tsv:
    type: File
    outputSource: run_itsonedb/krona_tsv

  itsonedb_otu_txt:
    type: File
    outputSource: run_itsonedb/krona_txt

  itsonedb_krona_image:
    type: File
    outputSource: run_itsonedb/krona_image

#  unite_hdf5_classifications:
#    type: File
#    outputSource: unite_otu_counts_to_hdf5/result

#  unite_json_classifications:
#    type: File
#    outputSource: unite_otu_counts_to_json/result

#  itsonedb_hdf5_classifications:
#    type: File
#    outputSource: itsonedb_otu_counts_to_hdf5/result

#  itsonedb_json_classifications:
#    type: File
#    outputSource: itsonedb_otu_counts_to_json/result



#ADD QUALITY CONTROLLED READS

steps:

  cat:
    run: ../tools/mask-for-ITS/cat-SSU-LSU.cwl
    in:
      SSU_coords: SSU_coordinates
      LSU_coords: LSU_coordinates
    out: [ all-coordinates ]

  match_proportion:
    run: ../tools/mask-for-ITS/divide.cwl
    in:
      all_coordinates: cat/all-coordinates
      summary: qc_stats_summary
      fasta: query_sequences
    out: [fasta_output]

  #if proportion < 0.90 then carry on, update with potential "conditional"
  #mask SSU/LSU
  reformat_coords:
    run: ../tools/mask-for-ITS/format-bedfile.cwl
    in:
      all_coordinates: cat/all-coordinates
    out: [ maskfile ]

  mask_for_ITS:
    run: ../tools/mask-for-ITS/bedtools.cwl
    in:
      sequences: match_proportion/fasta_output
      maskfile: reformat_coords/maskfile
    out: [masked_sequences]

#run unite and ITSonedb

  run_unite:
    run: classify-otu-visualise.cwl
    in:
      fasta: mask_for_ITS/masked_sequences
      mapseq_ref: unite_database
      mapseq_taxonomy: unite_taxonomy
      otu_ref: unite_otus
      otu_label: otu_unite_label
    out: [ mapseq_classifications, krona_tsv, krona_txt, krona_image, mapseq_json, mapseq_hdf5]

  run_itsonedb:
    run: classify-otu-visualise.cwl
    in:
      fasta: mask_for_ITS/masked_sequences
      mapseq_ref: itsone_database
      mapseq_taxonomy: itsone_taxonomy
      otu_ref: itsone_otus
      otu_label: otu_itsone_label
    out: [ mapseq_classifications, krona_tsv, krona_txt, krona_image, mapseq_json, mapseq_hdf5]
