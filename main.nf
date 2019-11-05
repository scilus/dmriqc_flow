#!/usr/bin/env nextflow

params.root = false
params.fa_template = false
params.help = false

if(params.help) {
    usage = file("$baseDir/USAGE")

    engine = new groovy.text.SimpleTemplateEngine()
    template = engine.createTemplate(usage.text).make()

    print template.toString()
    return
}

log.info "dMRIqc-Flow"
log.info "==========="
log.info ""
log.info "Start time: $workflow.start"
log.info ""

log.debug "[Command-line]"
log.debug "$workflow.commandLine"
log.debug ""

workflow.onComplete {
    log.info "Pipeline completed at: $workflow.complete"
    log.info "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
    log.info "Execution duration: $workflow.duration"
}

log.info "Input: $params.root"
root = file(params.root)

Channel
    .fromPath("$root/**/Segment_Tissues/*mask_wm.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .into{wm_for_resampled_dwi;wm_for_dti;wm_for_fodf;wm_for_registration}

Channel
    .fromPath("$root/**/Segment_Tissues/*mask_gm.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .into{gm_for_resampled_dwi;gm_for_dti;gm_for_fodf;gm_for_registration}

Channel
    .fromPath("$root/**/Segment_Tissues/*mask_csf.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .into{csf_for_resampled_dwi;csf_for_dti;csf_for_fodf;csf_for_registration}

Channel
    .fromPath("$root/**/Bet_DWI/*b0_bet_mask.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{b0_bet_mask_for_bet}

Channel
    .fromPath("$root/**/Eddy/*dwi_corrected.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{dwi_eddy_for_bet}

Channel
    .fromPath("$root/**/Eddy_Topup/*dwi_corrected.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{dwi_eddy_topup_for_bet}

dwi_eddy_for_bet
    .concat(dwi_eddy_topup_for_bet)
    .flatten()
    .toList()
    .set{dwi_for_bet}

process QC_Brain_Extraction_DWI {
    cpus params.bet_dwi_nb_threads

    input:
    file(mask) from b0_bet_mask_for_bet
    file(dwi) from dwi_for_bet

    output:
    file "report_dwi_bet.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_brain_extraction.py "Brain Extraction DWI" report_dwi_bet.html\
    --images_no_bet $dwi\
    --images_bet_mask $mask\
    --skip $params.bet_dwi_skip\
    --nb_threads $params.bet_dwi_nb_threads
    """
}

Channel
    .fromPath("$root/**/Bet_T1/*t1_bet_mask.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{t1_bet_mask_for_bet}

Channel
    .fromPath("$root/**/Resample_T1/*t1_resampled.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{t1_for_bet}

process QC_Brain_Extraction_T1 {
    cpus params.bet_t1_nb_threads

    input:
    file(mask) from t1_bet_mask_for_bet
    file(t1) from t1_for_bet

    output:
    file "report_t1_bet.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_brain_extraction.py "Brain Extraction T1" report_t1_bet.html\
    --images_no_bet $t1\
    --images_bet_mask $mask\
    --skip $params.bet_t1_skip\
    --nb_threads $params.bet_t1_nb_threads
    """
}

Channel
    .fromPath("$root/**/Denoise_DWI/*dwi_denoised.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{dwi_denoised}

process QC_Denoise_DWI {
    cpus params.denoise_dwi_nb_threads

    input:
    file(dwi) from dwi_denoised

    output:
    file "report_denoise_dwi.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_generic.py "Denoise DWI" report_denoise_dwi.html\
    --images $dwi\
    --skip $params.denoise_dwi_skip\
    --nb_threads $params.denoise_dwi_nb_threads
    """
}

Channel
    .fromPath("$root/**/Denoise_T1/*t1_denoised.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{t1_denoised}

process QC_Denoise_T1 {
    cpus params.denoise_t1_nb_threads

    input:
    file(t1) from t1_denoised

    output:
    file "report_denoise_t1.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_generic.py "Denoise T1" report_denoise_t1.html\
    --images $t1\
    --skip $params.denoise_t1_skip\
    --nb_threads $params.denoise_t1_nb_threads
    """
}

Channel
    .fromPath("$root/**/Bet_Prelim_DWI/*b0_bet.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .into{b0_for_eddy_topup;for_counter_eddy_topup}

Channel
    .fromPath("$root/**/Bet_Prelim_DWI/*b0_bet_mask_dilated.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{b0_mask_for_eddy_topup}

for_counter_eddy_topup
    .flatten()
    .count()
    .set{counter_b0}

Channel
    .fromPath("$root/**/Extract_B0/*b0.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{b0_corrected}

Channel
    .fromPath("$root/**/Eddy_Topup/*dwi_corrected.nii.gz", maxDepth:3)
    .map{it}
    .count()
    .set{eddy_topup_counter}

Channel
    .fromPath("$root/**/Eddy/*dwi_corrected.nii.gz", maxDepth:3)
    .map{it}
    .count()
    .set{eddy_counter}

process QC_Eddy_Topup {
    cpus params.eddy_topup_nb_threads

    input:
    file(b0) from b0_for_eddy_topup
    file(b0_corrected) from b0_corrected
    file(mask) from b0_mask_for_eddy_topup
    val(counter_b0_before) from counter_b0
    val(counter_b0_eddy_topup) from eddy_topup_counter
    val(counter_b0_eddy) from eddy_counter

    output:
    file "report_eddy_topup.html"
    file "data"
    file "libs"

    when:
    counter_b0_before == counter_b0_eddy_topup || counter_b0_before == counter_b0_eddy

    script:
    """
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
    paste b0.txt b0_corrected.txt mask.txt | while read a b c; do filename=\$(basename -- "\$b");\
    filename="\${filename%.*.*}"; mrcalc \$b \$c -mult \${filename}_corrected_masked.nii.gz;\
    mrcat \$a \${filename}_corrected_masked.nii.gz \${filename}_eddy_topup.nii.gz; done

    dmriqc_generic.py "Eddy Topup" report_eddy_topup.html\
    --images *_eddy_topup.nii.gz\
    --skip $params.eddy_topup_skip\
    --nb_threads $params.eddy_topup_nb_threads
    """
}

Channel
    .fromPath("$root/**/Resample_B0/*b0_resampled.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
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

    script:
    """
    dmriqc_generic.py "Resample DWI" report_resampled_dwi.html\
    --images $b0 --wm $wm --gm $gm --csf $csf\
    --skip $params.resample_dwi_skip\
    --nb_threads $params.resample_dwi_nb_threads
    """
}

Channel
    .fromPath("$root/**/Resample_T1/*t1_resampled.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{t1_resampled}

process QC_Resample_T1 {
    cpus params.resample_t1_nb_threads

    input:
    file(t1) from t1_resampled

    output:
    file "report_resampled_t1.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_generic.py "Resample T1" report_resampled_t1.html\
    --images $t1\
    --skip $params.resample_t1_skip\
    --nb_threads $params.resample_t1_nb_threads
    """
}

dti_metrics = Channel
    .fromFilePairs("$root/**/DTI_Metrics/*{fa.nii.gz,md.nii.gz,rd.nii.gz,ad.nii.gz,residual.nii.gz,evecs_v1.nii.gz}",
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
    .toSortedList()
    .set{fa_for_dti_qa}
md
    .flatten()
    .toSortedList()
    .set{md_for_dti_qa}
rd
    .flatten()
    .toSortedList()
    .set{rd_for_dti_qa}
ad
    .flatten()
    .toSortedList()
    .set{ad_for_dti_qa}
residual
    .flatten()
    .toSortedList()
    .set{residual_for_dti_qa}
evecs
    .flatten()
    .toSortedList()
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

    script:
    """
    dmriqc_dti.py report_dti.html\
    --fa $fa\
    --md $md\
    --rd $rd\
    --ad $ad\
    --residual $residual\
    --evecs_v1 $evecs_v1\
    --wm $wm --gm $gm --csf $csf\
    --skip $params.dti_skip\
    --nb_threads $params.dti_nb_threads
    """
}

Channel
    .fromPath("$root/**/Compute_FRF/*frf.txt", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{compute_frf}

process QC_Compute_FRF {
    cpus params.frf_nb_threads

    input:
    file(frf) from compute_frf

    output:
    file "report_compute_frf.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_frf.py $frf report_compute_frf.html
    """
}

fodf_metrics = Channel
    .fromFilePairs("$root/**/FODF_Metrics/*{afd_max.nii.gz,afd_sum.nii.gz,afd_total.nii.gz,nufo.nii.gz}",
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
    .toSortedList()
    .set{afd_max_for_fodf_qa}
afd_sum
    .flatten()
    .toSortedList()
    .set{afd_sum_for_fodf_qa}
afd_total
    .flatten()
    .toSortedList()
    .set{afd_total_for_fodf_qa}
nufo
    .flatten()
    .toSortedList()
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

    script:
    """
    dmriqc_fodf.py report_fodf.html\
    --afd_max $afd_max\
    --afd_sum $afd_sum\
    --afd_total $afd_total\
    --nufo $nufo\
    --wm $wm --gm $gm --csf $csf\
    --skip $params.fodf_skip\
    --nb_threads $params.fodf_nb_threads
    """
}

Channel
    .fromPath("$root/**/Tracking/*tracking.trk", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{tractograms}

Channel
    .fromPath("$root/**/Register_T1/*t1_warped.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .into{t1_warped_for_tracking;t1_warped_for_registration}

process QC_Tracking {
    cpus params.tracking_nb_threads

    input:
    file(tracking) from tractograms
    file(t1) from t1_warped_for_tracking

    output:
    file "report_tracking.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_tractogram.py report_tracking.html --tractograms $tracking --t1 $t1
    """
}

Channel
    .fromPath("$root/**/Segment_Tissues/*map_wm.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{wm_maps}

Channel
    .fromPath("$root/**/Segment_Tissues/*map_gm.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{gm_maps}

Channel
    .fromPath("$root/**/Segment_Tissues/*map_csf.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{csf_maps}

process QC_Segment_Tissues {
    cpus params.segment_tissues_nb_threads

    input:
    file(wm) from wm_maps
    file(gm) from gm_maps
    file(csf) from csf_maps

    output:
    file "report_segment_tissues.html"
    file "data"
    file "libs"

    script:
    """
    dmriqc_tissues.py report_segment_tissues.html\
    --wm $wm --gm $gm --csf $csf\
    --skip $params.segment_tissues_skip\
    --nb_threads $params.segment_tissues_nb_threads
    """
}

Channel
    .fromPath("$root/**/Seeding_Mask/*seeding_mask.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{seeding}

Channel
    .fromPath("$root/**/PFT_Maps/*map_include.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
    .set{include}

Channel
    .fromPath("$root/**/PFT_Maps/*map_exclude.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
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

    script:
    """
    dmriqc_tracking_maps.py pft report_pft_maps.html\
    --seeding_mask $seeding_mask --map_include $map_include\
    --map_exclude $map_exclude\
    --skip $params.pft_maps_skip\
    --nb_threads $params.pft_maps_nb_threads
    """
}

Channel
    .fromPath("$root/**/DTI_Metrics/*rgb.nii.gz", maxDepth:3)
    .map{it}
    .toSortedList()
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

    script:
    """
    dmriqc_registration.py report_registration.html\
    --t1 $t1 --rgb $rgb\
    --wm $wm --gm $gm --csf $csf\
    --skip $params.register_skip\
    --nb_threads $params.register_nb_threads
    """
}
