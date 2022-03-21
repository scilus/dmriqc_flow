# dmriqc_flow
A Nextflow pipeline for diffusion MRI quality check.


### Tools
QC available for these tools:

- [Tractoflow](https://github.com/scilus/tractoflow) (-profile tractoflow_qc_light or -profile tractoflow_qc_all)
- [RBX_flow](https://github.com/scilus/rbx_flow) (-profile rbx_qc)
- [Disconets_flow](https://github.com/scilus/disconets_flow) (-profile disconets_qc)

QC available also for raw input structure like BIDS or tractoflow input structure. (-profile input_qc)

### Build singularity or docker image
```
# Singularity
sudo singularity build scilus_1.3.0.sif docker://scilus/scilus:1.3.0

# Docker
sudo docker pull scilus/scilus:1.3.0
```

### Nextflow version

Please use nextflow 21.*
