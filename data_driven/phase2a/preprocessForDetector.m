function I_proc = preprocessForDetector(I, muChannel, sigmaChannel)
% preprocessForDetector  Phase 2a/v1 detector preprocessing.
%
% v6.2 Stage H / Phase 3: apply the same inference preprocessing used for
% the Phase 2a v1 model. CLAHE is from L03/Lab02 LNORM (✅ Verified in the
% project plan); manual per-channel z-score follows L08 s156 / L09 s173
% (✅ Verified). This is intentionally restored for v1 evaluation because the
% saved v1 detector was trained with these preprocessed tensors.

    if size(I, 3) == 1
        I = repmat(I, 1, 1, 3);
    elseif size(I, 3) > 3
        I = I(:, :, 1:3);
    end

    if isa(I, 'uint8')
        I8 = I;
    else
        I8 = im2uint8(I);
    end

    Lab = rgb2lab(I8);
    Lab(:, :, 1) = adapthisteq(Lab(:, :, 1) / 100) * 100;
    I_clahe = lab2rgb(Lab);
    I_clahe255 = single(I_clahe) * 255;

    sigmaSafe = single(sigmaChannel);
    sigmaSafe(sigmaSafe == 0) = 1;
    I_proc = (I_clahe255 - reshape(single(muChannel), 1, 1, 3)) ./ ...
        reshape(sigmaSafe, 1, 1, 3);
end
