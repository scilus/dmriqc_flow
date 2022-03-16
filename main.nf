#!/usr/bin/env nextflow

params.input = false
params.fa_template = false
params.help = false

if(params.help) {
    usage = file("$baseDir/USAGE")
    bindings = ["dicom_fields":"$params.dicom_fields"]
    engine = new groovy.text.SimpleTemplateEngine()
    template = engine.createTemplate(usage.text).make(bindings)
    print template.toString()
    return
}

log.info "dMRIqc_flow"
log.info "==========="
log.info ""
log.info "Start time: $workflow.start"
log.info ""

log.info "[Profile]"
log.info "$workflow.profile"
log.info ""

workflow.onComplete {
    log.info "Pipeline completed at: $workflow.complete"
    log.info "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
    log.info "Execution duration: $workflow.duration"
}

String[] theArr = workflow.profile.split(",");
List<String> profiles = new ArrayList<String>();
for (String item : theArr) {
   profiles.add(item);
}

if (profiles.get(0) != "input_qc" && profiles.get(0) != "tractoflow_qc_light" && profiles.get(0) != "tractoflow_qc_all" && profiles.get(0) != "rbx_qc")
{
    error "Error ~ Please select a profile (-profile): input_qc, tractoflow_qc_light, tractoflow_qc_all or rbx_qc."
}


if (params.input){
    log.info "Input: $params.input"
    input = file(params.input)
}
else {
    error "Error ~ Please use --input for the input data."
}


Channel
    .fromPath("$input/**/Segment_*/*mask_wm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .into{wm_for_resampled_dwi;wm_for_dti;wm_for_fodf;wm_for_registration}

Channel
    .fromPath("$input/**/Segment_*/*mask_gm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .into{gm_for_resampled_dwi;gm_for_dti;gm_for_fodf;gm_for_registration}

Channel
    .fromPath("$input/**/Segment_*/*mask_csf.nii.gz", maxDepth:3)
    .collect(sort:true)
    .into{csf_for_resampled_dwi;csf_for_dti;csf_for_fodf;csf_for_registration}

Channel
    .fromPath("$input/**/Bet_DWI/*b0_bet_mask.nii.gz", maxDepth:3)
    .collect(sort:true)
    .map{[it]}
    .set{b0_bet_mask_for_bet}

Channel
    .fromPath(["$input/**/Eddy/*dwi_corrected.nii.gz", "$input/**/Eddy_Topup/*dwi_corrected.nii.gz"], maxDepth:3)
    .collect(sort:true)
    .map{[it]}
    .set{dwi_eddy_for_bet}

dwi_eddy_for_bet.combine(b0_bet_mask_for_bet).set{dwi_mask_for_bet}

process QC_Brain_Extraction_DWI {
    cpus params.bet_dwi_nb_threads

    input:
    tuple file(dwi), file(mask) from dwi_mask_for_bet

    output:
    file "report_dwi_bet.html"
    file "data"
    file "libs"

    when:
        params.run_qc_bet_dwi

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {no_bet,bet_mask}
    mv *dwi*.nii.gz no_bet/
    mv *b0_bet_mask.nii.gz bet_mask/

    dmriqc_brain_extraction.py "Brain Extraction DWI" report_dwi_bet.html\
    --no_bet no_bet/\
    --bet_mask bet_mask\
    --skip $params.bet_dwi_skip\
    --nb_threads $params.bet_dwi_nb_threads\
    --nb_columns $params.bet_dwi_nb_columns
    """
}

Channel
    .fromPath("$input/**/Bet_T1/*t1_bet_mask.nii.gz", maxDepth:3)
    .collect(sort:true)
    .map{[it]}
    .set{t1_bet_mask_for_bet}

Channel
    .fromPath("$input/**/Resample_T1/*t1_resampled.nii.gz",
      maxDepth:3)
    .collect(sort:true)
    .map{[it]}
    .set{t1_for_bet}

t1_for_bet.combine(t1_bet_mask_for_bet).set{t1_mask_for_bet}

process QC_Brain_Extraction_T1 {
    cpus params.bet_t1_nb_threads

    input:
    tuple file(t1), file(mask) from t1_mask_for_bet

    output:
    file "report_t1_bet.html"
    file "data"
    file "libs"

    when:
        params.run_qc_bet_t1

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {no_bet,bet_mask}
    mv *t1_bet_mask.nii.gz bet_mask/
    mv *.nii.gz no_bet/

    dmriqc_brain_extraction.py "Brain Extraction T1" report_t1_bet.html\
    --no_bet no_bet\
    --bet_mask bet_mask\
    --skip $params.bet_t1_skip\
    --nb_threads $params.bet_t1_nb_threads\
    --nb_columns $params.bet_t1_nb_columns
    """
}

Channel
    .fromPath("$input/**/Denoise_DWI/*dwi_denoised.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{dwi_denoised}

process QC_Denoise_DWI {
    cpus params.denoise_dwi_nb_threads

    input:
    file(dwi) from dwi_denoised

    output:
    file "report_denoise_dwi.html"
    file "data"
    file "libs"

    when:
        params.run_qc_denoise_dwi

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *dwi_denoised.nii.gz images/

    dmriqc_generic.py "Denoise DWI" report_denoise_dwi.html\
    --images images\
    --skip $params.denoise_dwi_skip\
    --nb_threads $params.denoise_dwi_nb_threads\
    --nb_columns $params.denoise_dwi_nb_columns
    """
}

Channel
    .fromPath("$input/**/Denoise_T1/*t1_denoised.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{t1_denoised}

process QC_Denoise_T1 {
    cpus params.denoise_t1_nb_threads

    input:
    file(t1) from t1_denoised

    output:
    file "report_denoise_t1.html"
    file "data"
    file "libs"

    when:
        params.run_qc_denoise_t1

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *t1_denoised.nii.gz images/

    dmriqc_generic.py "Denoise T1" report_denoise_t1.html\
    --images images\
    --skip $params.denoise_t1_skip\
    --nb_threads $params.denoise_t1_nb_threads\
    --nb_columns $params.denoise_t1_nb_columns
    """
}

Channel
    .fromPath(["$input/**/Bet_Prelim_DWI/*b0_bet.nii.gz"],
      maxDepth:3)
    .collect(sort:true)
    .into{b0_for_eddy_topup;for_counter_b0;toto}

Channel
    .fromPath("$input/**/Bet_DWI/*b0_bet_mask.nii.gz",
      maxDepth:3)
    .collect(sort:true)
    .into{b0_mask_for_eddy_topup;truc}

Channel
    .fromPath(["$input/**/Extract_B0/*b0.nii.gz","$input/**/Bet_DWI/*b0_no_bet.nii.gz"], maxDepth:3)
    .collect(sort:true)
    .into{b0_corrected;for_counter_b0_corrected}

for_counter_b0
    .flatten()
    .count()
    .set{counter_b0}

for_counter_b0_corrected
    .flatten()
    .count()
    .set{counter_b0_eddy}

process QC_Eddy_Topup {
    cpus params.eddy_topup_nb_threads

    input:
    file(b0) from b0_for_eddy_topup
    file(b0_corrected) from b0_corrected
    file(mask) from b0_mask_for_eddy_topup
    val(counter_b0_before) from counter_b0
    val(counter_b0_corrected) from counter_b0_eddy

    output:
    file "report_eddy_topup.html"
    file "data"
    file "libs"

    when:
    (counter_b0_before == counter_b0_corrected) && params.run_qc_eddy_topup

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    for i in $b0
    do
        echo \$i >> b0.txt
    done
    for i in $b0_corrected
    do
        echo \$i >> b0_corrected.txt
    done
    for i in $mask
    do
        echo \$i >> mask.txt
    done
    mkdir images
    paste b0.txt b0_corrected.txt mask.txt | while read a b c; do filename=\$(basename -- "\$b");\
    filename="\${filename%.*.*}"; mrcalc \$b \$c -mult \${filename}_corrected_masked.nii.gz;\
    mrcat \$a \${filename}_corrected_masked.nii.gz images/\${filename}_eddy_topup.nii.gz; done

    dmriqc_generic.py "Eddy Topup" report_eddy_topup.html\
    --images images\
    --skip $params.eddy_topup_skip\
    --nb_threads $params.eddy_topup_nb_threads\
    --nb_columns $params.eddy_topup_nb_columns\
    --duration $params.eddy_topup_duration
    """
}

Channel
    .fromPath("$input/**/*_B0/*b0_resampled.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{b0_resampled}

process QC_Resample_DWI {
    cpus params.resample_dwi_nb_threads

    input:
    file(b0) from b0_resampled
    file(wm) from wm_for_resampled_dwi
    file(gm) from gm_for_resampled_dwi
    file(csf) from csf_for_resampled_dwi

    output:
    file "report_resampled_dwi.html"
    file "data"
    file "libs"

    when:
        params.run_qc_resample_dwi

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {images,wm,csf,gm}
    mv *b0_resampled.nii.gz images/
    for i in wm csf gm
    do
      mv *\${i}.nii.gz \${i}/
    done

    dmriqc_generic.py "Resample DWI" report_resampled_dwi.html\
    --images images --wm wm --gm gm --csf csf\
    --skip $params.resample_dwi_skip\
    --nb_threads $params.resample_dwi_nb_threads\
    --nb_columns $params.resample_dwi_nb_columns
    """
}

Channel
    .fromPath("$input/**/Resample_T1/*t1_resampled.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{t1_resampled}

process QC_Resample_T1 {
    cpus params.resample_t1_nb_threads

    input:
    file(t1) from t1_resampled

    output:
    file "report_resampled_t1.html"
    file "data"
    file "libs"

    when:
        params.run_qc_resample_t1

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *t1_resampled.nii.gz images/

    dmriqc_generic.py "Resample T1" report_resampled_t1.html\
    --images images\
    --skip $params.resample_t1_skip\
    --nb_threads $params.resample_t1_nb_threads\
    --nb_columns $params.resample_t1_nb_columns
    """
}

dti_metrics = Channel
    .fromFilePairs("$input/**/DTI_Metrics/*{fa.nii.gz,md.nii.gz,rd.nii.gz,ad.nii.gz,residual.nii.gz,evecs_v1.nii.gz}",
                    size: 6,
                    maxDepth:3,
                    flat:true)

(fa, md, rd, ad, residual, evecs) = dti_metrics
    .map{sid, ad, evecs, fa, md, rd, residual -> [tuple(fa),
                              tuple(md),
                              tuple(rd),
                              tuple(ad),
                              tuple(residual),
                              tuple(evecs)]}
    .separate(6)

fa
    .flatten()
    .collect(sort:true)
    .set{fa_for_dti_qa}
md
    .flatten()
    .collect(sort:true)
    .set{md_for_dti_qa}
rd
    .flatten()
    .collect(sort:true)
    .set{rd_for_dti_qa}
ad
    .flatten()
    .collect(sort:true)
    .set{ad_for_dti_qa}
residual
    .flatten()
    .collect(sort:true)
    .set{residual_for_dti_qa}
evecs
    .flatten()
    .collect(sort:true)
    .set{evecs_for_dti_qa}

process QC_DTI {
    cpus params.dti_nb_threads

    input:
    file(fa) from fa_for_dti_qa
    file(md) from md_for_dti_qa
    file(rd) from rd_for_dti_qa
    file(ad) from ad_for_dti_qa
    file(residual) from residual_for_dti_qa
    file(evecs_v1) from evecs_for_dti_qa
    file(wm) from wm_for_dti
    file(gm) from gm_for_dti
    file(csf) from csf_for_dti

    output:
    file "report_dti.html"
    file "data"
    file "libs"

    when:
        params.run_qc_dti

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {fa,md,rd,ad,residual,evecs_v1,wm,gm,csf}

    for i in fa md rd ad residual evecs_v1 wm csf gm
    do
      mv *\${i}.nii.gz \${i}/;
    done

    dmriqc_dti.py report_dti.html\
    --fa fa\
    --md md\
    --rd rd\
    --ad ad\
    --residual residual\
    --evecs_v1 evecs_v1\
    --wm wm --gm gm --csf csf\
    --skip $params.dti_skip\
    --nb_threads $params.dti_nb_threads\
    --nb_columns $params.dti_nb_columns
    """
}

Channel
    .fromPath("$input/**/Compute_FRF/*frf.txt", maxDepth:3)
    .collect(sort:true)
    .set{compute_frf}

process QC_FRF {
    cpus params.frf_nb_threads

    input:
    file(frf) from compute_frf

    output:
    file "report_compute_frf.html"
    file "libs"

    when:
        params.run_qc_frf

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *frf.txt images/

    dmriqc_frf.py images report_compute_frf.html
    """
}

fodf_metrics = Channel
    .fromFilePairs("$input/**/FODF_Metrics/*{afd_max.nii.gz,afd_sum.nii.gz,afd_total.nii.gz,nufo.nii.gz}",
                    size: 4,
                    maxDepth:3,
                    flat:true)

(afd_max, afd_sum, afd_total, nufo) = fodf_metrics
    .map{sid, afd_max, afd_sum, afd_total, nufo -> [tuple(afd_max),
                              tuple(afd_sum),
                              tuple(afd_total),
                              tuple(nufo)]}
    .separate(4)

afd_max
    .flatten()
    .collect(sort:true)
    .set{afd_max_for_fodf_qa}
afd_sum
    .flatten()
    .collect(sort:true)
    .set{afd_sum_for_fodf_qa}
afd_total
    .flatten()
    .collect(sort:true)
    .set{afd_total_for_fodf_qa}
nufo
    .flatten()
    .collect(sort:true)
    .set{nufo_for_fodf_qa}

process QC_FODF {
    cpus params.fodf_nb_threads

    input:
    file(afd_max) from afd_max_for_fodf_qa
    file(afd_sum) from afd_sum_for_fodf_qa
    file(afd_total) from afd_total_for_fodf_qa
    file(nufo) from nufo_for_fodf_qa
    file(wm) from wm_for_fodf
    file(gm) from gm_for_fodf
    file(csf) from csf_for_fodf

    output:
    file "report_fodf.html"
    file "data"
    file "libs"

    when:
        params.run_qc_fodf

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {afd_max,afd_sum,afd_total,nufo,wm,csf,gm}
    for i in afd_max afd_sum afd_total nufo wm csf gm
    do
      mv *\${i}.nii.gz \${i}/;
    done

    dmriqc_fodf.py report_fodf.html\
    --afd_max afd_max\
    --afd_sum afd_sum\
    --afd_total afd_total\
    --nufo nufo\
    --wm wm --gm gm --csf csf\
    --skip $params.fodf_skip\
    --nb_threads $params.fodf_nb_threads\
    --nb_columns $params.fodf_nb_columns
    """
}

Channel
    .fromPath("$input/**/*_Tracking/*.trk", maxDepth:3)
    .map{["report", it.parent.parent.name, it]}
    .set{tractograms}

Channel
    .fromPath("$input/**/Register_T1/*t1_warped.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{t1_warped_for_registration}

Channel
    .fromPath("$input/**/Register_T1/*t1_warped.nii.gz", maxDepth:3)
    .map{["report", it.parent.parent.name, it]}
    .set{t1_warped_for_tracking}

tractograms
    .combine(t1_warped_for_tracking, by:[0,1])
    .groupTuple()
    .map{it -> it[2..-1]}
    .set{tracking_t1}

process QC_Tracking {
    cpus params.tracking_nb_threads

    input:
    set file(tracking), file("*warped.nii.gz") from tracking_t1

    output:
    file "report_tracking.html"
    file "data"
    file "libs"

    when:
        params.run_qc_tracking

    script:
    """
    mkdir -p {anat,trks}
    mv *warped.nii.gz anat/
    mv *.trk trks/

    dmriqc_tractogram.py report_tracking.html --tractograms trks --t1 anat
    """
}

Channel
    .fromPath("$input/**/Segment_Tissues/*map_wm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{wm_maps}

Channel
    .fromPath("$input/**/Segment_Freesurfer/*mask_wm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{wm_masks}

wm_maps
  .mix(wm_masks)
  .collect(sort:true)
  .set{wm_for_seg}

Channel
    .fromPath("$input/**/Segment_Tissues/*map_gm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{gm_maps}

Channel
    .fromPath("$input/**/Segment_Freesurfer/*mask_gm.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{gm_masks}

gm_maps
  .mix(gm_masks)
  .collect(sort:true)
  .set{gm_for_seg}

Channel
    .fromPath("$input/**/Segment_Tissues/*map_csf.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{csf_maps}

Channel
    .fromPath("$input/**/Segment_Freesurfer/*mask_csf.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{csf_masks}

csf_maps
  .mix(csf_masks)
  .collect(sort:true)
  .set{csf_for_seg}

process QC_Segment_Tissues {
    cpus params.segment_tissues_nb_threads

    input:
    file(wm) from wm_for_seg
    file(gm) from gm_for_seg
    file(csf) from csf_for_seg

    output:
    file "report_segment_tissues.html"
    file "data"
    file "libs"

    when:
        params.run_qc_segment_tissues

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {wm,csf,gm}
    for i in wm csf gm
    do
      mv *\${i}.nii.gz \${i}/;
    done

    dmriqc_tissues.py report_segment_tissues.html\
    --wm wm --gm gm --csf csf\
    --skip $params.segment_tissues_skip\
    --nb_threads $params.segment_tissues_nb_threads\
    --nb_columns $params.segment_tissues_nb_columns
    """
}

Channel
    .fromPath("$input/**/PFT_Seeding_Mask/*seeding_mask.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{seeding}

Channel
    .fromPath("$input/**/PFT_Tracking_Maps/*map_include.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{include}

Channel
    .fromPath("$input/**/PFT_Tracking_Maps/*map_exclude.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{exclude}

process QC_PFT_Maps {
    cpus params.pft_maps_nb_threads

    input:
    file(seeding_mask) from seeding
    file(map_include) from include
    file(map_exclude) from exclude

    output:
    file "report_pft_maps.html"
    file "data"
    file "libs"

    when:
        params.run_qc_pft_maps && seeding_mask.size()

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {seeding_mask,map_include,map_exclude}
    for i in seeding_mask map_include map_exclude
    do
      mv *\${i}.nii.gz \${i}/;
    done

    dmriqc_tracking_maps.py pft report_pft_maps.html\
    --seeding_mask seeding_mask --map_include map_include\
    --map_exclude map_exclude\
    --skip $params.pft_maps_skip\
    --nb_threads $params.pft_maps_nb_threads\
    --nb_columns $params.pft_maps_nb_columns
    """
}

Channel
    .fromPath("$input/**/Local_Tracking_Mask/*tracking_mask.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{mask}

process QC_Local_Tracking_Mask {
    cpus params.local_tracking_mask_nb_threads

    input:
    file(tracking_mask) from mask

    output:
    file "report_local_tracking_mask.html"
    file "data"
    file "libs"

    when:
        params.run_qc_tracking_mask && tracking_mask.size()

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *tracking_mask.nii.gz images/

    dmriqc_generic.py "Tracking mask" report_local_tracking_mask.html\
        --images images\
        --skip $params.local_tracking_mask_skip\
        --nb_threads $params.local_tracking_mask_nb_threads\
        --nb_columns $params.local_tracking_mask_nb_columns
    """
}

Channel
    .fromPath("$input/**/Local_Seeding_Mask/*seeding_mask.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{seeding}

process QC_Local_Seeding_Mask {
    cpus params.local_seeding_mask_nb_threads

    input:
    file(seeding_mask) from seeding

    output:
    file "report_local_seeding_mask.html"
    file "data"
    file "libs"

    when:
        params.run_qc_seeding_mask && seeding_mask.size()

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *seeding_mask.nii.gz images/

    dmriqc_generic.py "Seeding mask" report_local_seeding_mask.html\
            --images images\
            --skip $params.local_seeding_mask_skip\
            --nb_threads $params.local_seeding_mask_nb_threads\
            --nb_columns $params.local_seeding_mask_nb_columns
    """
}

Channel
    .fromPath("$input/**/DTI_Metrics/*rgb.nii.gz", maxDepth:3)
    .collect(sort:true)
    .set{rgb}

process QC_Register_T1 {
    cpus params.register_nb_threads

    input:
    file(t1) from t1_warped_for_registration
    file(rgb) from rgb
    file(wm) from wm_for_registration
    file(gm) from gm_for_registration
    file(csf) from csf_for_registration

    output:
    file "report_registration.html"
    file "data"
    file "libs"

    when:
        params.run_qc_register_t1

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {t1_warped,rgb,wm,csf,gm}
    for i in t1_warped rgb wm csf gm
    do
      mv *\${i}.nii.gz \${i}/;
    done

    dmriqc_registration.py report_registration.html\
    --t1 t1_warped --rgb rgb\
    --wm wm --gm gm --csf csf\
    --skip $params.register_skip\
    --nb_threads $params.register_nb_threads\
    --nb_columns $params.register_nb_columns
    """
}

Channel
    .fromPath("$input/**/*bval", maxDepth:1)
    .collect(sort:true)
    .set{all_raw_bval}

Channel
    .fromPath("$input/sub-*/**/*dwi.bval", maxDepth:4)
    .collect(sort:true)
    .set{all_bids_bval}

all_raw_bval
  .mix(all_bids_bval)
  .collect(sort:true)
  .set{all_bval}

Channel
  .fromPath("$input/sub-*/**/*dwi.json", maxDepth:4)
  .map{it}
  .toSortedList()
  .set{all_bids_json}

Channel
  .fromPath("$input/**/*dwi.json", maxDepth:1)
  .map{it}
  .toSortedList()
  .set{all_raw_json}

all_raw_json
  .mix(all_bids_json)
  .collect(sort:true)
  .set{all_json}

Channel
    .fromPath("$input/**/*bvec", maxDepth:1)
    .collect(sort:true)
    .set{all_raw_bvec}

Channel
    .fromPath("$input/sub-*/**/*dwi.bvec", maxDepth:4)
    .collect(sort:true)
    .set{all_bids_bvec}

all_raw_bvec
  .mix(all_bids_bvec)
  .collect(sort:true)
  .set{all_bvec}


process QC_DWI_Protocol {
    cpus 1

    input:
    file(bval) from all_bval
    file(bvec) from all_bvec
    file(json) from all_json

    output:
    file "report_dwi_protocol.html"
    file "data"
    file "libs"

    when:
        params.run_qc_dwi_protocol

    script:
    def metadata = json.name != [] ? "--metadata json_f" : ''
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir -p {bval_f,bvec_f,json_f}
    for i in bval bvec json
    do
      mv *\${i} \${i}_f/;
    done

    dmriqc_dwi_protocol.py report_dwi_protocol.html\
    --bval bval_f --bvec bvec_f\
    $metadata\
    --dicom_fields $params.dicom_fields\
    --tol $params.dwi_protocol_tol
    """
}

Channel
    .fromPath("$input/**/*t1.nii.gz", maxDepth:2)
    .collect(sort:true)
    .set{all_raw_t1}

Channel
    .fromPath("$input/sub-*/**/*T1w.nii.gz", maxDepth:4)
    .collect(sort:true)
    .set{all_bids_t1}

all_raw_t1
  .mix(all_bids_t1)
  .collect(sort:true)
  .set{all_t1}

process QC_Raw_T1 {
    cpus params.raw_t1_nb_threads

    input:
    file(t1) from all_t1

    output:
    file "report_raw_t1.html"
    file "data"
    file "libs"

    when:
        params.run_raw_t1

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *gz images/

    dmriqc_generic.py "Raw_T1" report_raw_t1.html\
        --images images\
        --skip $params.raw_t1_skip\
        --nb_threads $params.raw_t1_nb_threads\
        --nb_columns $params.raw_t1_nb_columns
    """
}

Channel
    .fromPath("$input/**/*dwi.nii.gz", maxDepth:1)
    .collect(sort:true)
    .set{all_raw_dwi}

Channel
    .fromPath("$input/sub-*/**/*dwi.nii.gz", maxDepth:4)
    .collect(sort:true)
    .set{all_bids_dwi}

all_raw_dwi
  .mix(all_bids_dwi)
  .collect(sort:true)
  .set{all_dwi}

process QC_Raw_DWI {
    cpus params.raw_dwi_nb_threads

    input:
    file(dwi) from all_dwi

    output:
    file "report_raw_dwi.html"
    file "data"
    file "libs"

    when:
        params.run_raw_dwi

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mkdir images
    mv *gz images/

    dmriqc_generic.py "Raw_DWI" report_raw_dwi.html\
        --images images\
        --skip $params.raw_dwi_skip\
        --nb_threads $params.raw_dwi_nb_threads\
        --nb_columns $params.raw_dwi_nb_columns
    """
}

anat_rbx = Channel
    .fromFilePairs("$params.input/**/Register_Anat/*native_anat.nii.gz",
              maxDepth: 2,
              size: 1,
              flat: true) { it.parent.parent.name }

bundles_rbx = Channel
    .fromFilePairs("$params.input/**/Clean_Bundles/*.trk",
                   maxDepth: 2,
                   size: -1) { it.parent.parent.name }

bundles_rbx
    .flatMap{ sid, bundles -> bundles.collect{ [sid, it] } }
    .map{sid, bundle -> [sid, bundle.getName().replace(sid, "").replace(".trk", "").replace("__", "").replace("_L", "").replace("_R", ""), bundle]}
    .groupTuple(by: [0,1])
    .combine(anat_rbx, by:0)
    .set{bundles_anat_for_screenshots}

process Screenshots_RBx {
    cpus 2
    stageInMode 'copy'
    publishDir {"./results_QC/$task.process/${sid}"}

    input:
    set sid, b_name, file(bundles), file(anat) from bundles_anat_for_screenshots

    output:
    set b_name, val("QC"), "${sid}__${b_name}.png" into screenshots_for_report

    when:
        params.run_qc_rbx

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    mrconvert $anat anat.nii.gz
    scil_visualize_bundles_mosaic.py anat.nii.gz $bundles ${sid}__${b_name}.png -f --light_screenshot --no_information
    """
}

screenshots_for_report
    .groupTuple(by: 1, sort:true)
    .map{b_names, _, bundles -> [b_names.unique().join(",").replaceAll(",", " "), bundles].toList()}
    .set{screenshots_for_qc_rbx}

process QC_RBx {
    cpus 1

    input:
    set b_names, file(bundles) from screenshots_for_qc_rbx

    output:
    file "report_rbx.html"
    file "data"
    file "libs"

    when:
        params.run_qc_rbx

    script:
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    for i in $b_names;
    do
        echo \${i}
        mkdir -p \${i}
        mv *\${i}.png \${i}/
    done
    dmriqc_from_screenshot.py report_rbx.html --data ${b_names} --sym_link
    """
}
