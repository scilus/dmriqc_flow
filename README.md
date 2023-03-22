# dmriqc_flow
A Nextflow pipeline for diffusion MRI quality check.


### Tools
QC is available for these tools:

- [Tractoflow](https://github.com/scilus/tractoflow) (-profile tractoflow_qc_light or -profile tractoflow_qc_all)
- [RBX_flow](https://github.com/scilus/rbx_flow) (-profile rbx_qc)
- [Disconets_flow](https://github.com/scilus/disconets_flow) (-profile disconets_qc)

QC is available also for raw input structure like BIDS or tractoflow input structure. (-profile input_qc)

### Build singularity or docker image
```
# Singularity
sudo singularity build scilus_1.4.2.sif docker://scilus/scilus:1.4.2

# Docker
sudo docker pull scilus/scilus:1.4.2
```

### Nextflow version

Please use nextflow 21.*

If you use this tool for your research, **please cite the following**

```
G. Theaud and M. Descoteaux,
“dMRIQCpy: a python-based toolbox for diffusion MRI quality control and beyond”,
International Symposium in Magnetic Resonance in Medicine (ISMRM 2022).
```
