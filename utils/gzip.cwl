#!/usr/bin/env
cwlVersion: v1.0
class: CommandLineTool

requirements:
  InlineJavascriptRequirement: {}
  ResourceRequirement:
    coresMax: 16
    ramMin: 5000

inputs:
  uncompressed_file:
    type: File
    inputBinding:
      position: 1

baseCommand: [ pigz ]
arguments: ["-p", "16", "-c"]

stdout: $(inputs.uncompressed_file.basename).gz

outputs:
  compressed_file:
    type: stdout

hints:
  - class: DockerRequirement
    dockerPull: alpine:3.7

s:license: "https://www.apache.org/licenses/LICENSE-2.0"
s:copyrightHolder: "EMBL - European Bioinformatics Institute"
