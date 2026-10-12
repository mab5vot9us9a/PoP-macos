// Build a full tessellation-emulation mesh pipeline from Pagonia's DXIL VS/HS/DS/PS
// using the Metal Shader Converter C API, the same way Apple's runtime helper does.
// Build: see build.sh. Usage: ./tess_pipeline VS.dxbc HS.dxbc DS.dxbc PS.dxbc [--dump DIR]
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <metal_irconverter/metal_irconverter.h>
#define IR_PRIVATE_IMPLEMENTATION
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

struct SigElem { std::string name; uint32_t idx, sysval, comp, reg; uint8_t mask; };

static std::vector<uint8_t> readFile(const char* p) {
    std::vector<uint8_t> v; FILE* f = fopen(p, "rb"); if (!f) return v;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n); fread(v.data(), 1, n, f); fclose(f); return v;
}

static std::vector<SigElem> parseSig(const std::vector<uint8_t>& d, const char* fourcc) {
    std::vector<SigElem> out;
    uint32_t n; memcpy(&n, d.data() + 28, 4);
    for (uint32_t i = 0; i < n; i++) {
        uint32_t off; memcpy(&off, d.data() + 32 + 4 * i, 4);
        if (memcmp(d.data() + off, fourcc, 4)) continue;
        const uint8_t* c = d.data() + off + 8;
        uint32_t cnt, base; memcpy(&cnt, c, 4); memcpy(&base, c + 4, 4);
        for (uint32_t j = 0; j < cnt; j++) {
            const uint8_t* e = c + base + j * 32;
            SigElem s; uint32_t nameoff;
            memcpy(&nameoff, e + 4, 4); memcpy(&s.idx, e + 8, 4); memcpy(&s.sysval, e + 12, 4);
            memcpy(&s.comp, e + 16, 4); memcpy(&s.reg, e + 20, 4); s.mask = e[24];
            s.name = (const char*)(c + nameoff);
            out.push_back(s);
        }
    }
    return out;
}

static IRFormat formatFor(const SigElem& s, uint32_t* size) {
    int n = __builtin_popcount(s.mask);
    *size = 4 * n;
    if (s.comp == 3) return n == 1 ? IRFormatR32Float : n == 2 ? IRFormatR32G32Float : n == 3 ? IRFormatR32G32B32Float : IRFormatR32G32B32A32Float;
    if (s.comp == 1) return n == 1 ? IRFormatR32Uint : n == 2 ? IRFormatR32G32Uint : IRFormatR32G32B32A32Uint;
    return n == 1 ? IRFormatR32Sint : IRFormatR32G32B32A32Sint;
}

static const char* errText(IRError* e) {
    if (!e) return "(no IRError)";
    const char* p = (const char*)IRErrorGetPayload(e);
    return p ? p : "(no payload)";
}

static IRObject* compile(IRCompiler* comp, const std::vector<uint8_t>& dxil, const char* label) {
    IRObject* in = IRObjectCreateFromDXIL(dxil.data(), dxil.size(), IRBytecodeOwnershipNone);
    IRError* err = nullptr;
    IRObject* out = IRCompilerAllocCompileAndLink(comp, nullptr, in, &err);
    if (!out) { printf("FAIL convert %s: code=%u %s\n", label, err ? IRErrorGetCode(err) : 0, errText(err)); if (err) IRErrorDestroy(err); }
    IRObjectDestroy(in);
    return out;
}

static id<MTLLibrary> makeLib(id<MTLDevice> dev, IRMetalLibBinary* bin, const char* label, const char* dumpDir, const char* dumpName) {
    dispatch_data_t dd = IRMetalLibGetBytecodeData(bin);
    if (dumpDir) {
        size_t n = IRMetalLibGetBytecodeSize(bin); std::vector<uint8_t> buf(n); IRMetalLibGetBytecode(bin, buf.data());
        std::string p = std::string(dumpDir) + "/" + dumpName; FILE* f = fopen(p.c_str(), "wb"); fwrite(buf.data(), 1, n, f); fclose(f);
    }
    NSError* e = nil;
    id<MTLLibrary> lib = [dev newLibraryWithData:dd error:&e];
    if (!lib) printf("FAIL newLibrary %s: %s\n", label, e.localizedDescription.UTF8String);
    return lib;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 5) { fprintf(stderr, "usage: %s VS HS DS PS [--dump DIR]\n", argv[0]); return 2; }
        const char* dumpDir = nullptr; bool useMtl4 = false;
        for (int i = 5; i < argc; i++) { if (!strcmp(argv[i], "--dump") && i + 1 < argc) dumpDir = argv[i + 1]; if (!strcmp(argv[i], "--mtl4")) useMtl4 = true; }
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        bool noPS = !strcmp(argv[4], "none");
        auto vsB = readFile(argv[1]), hsB = readFile(argv[2]), dsB = readFile(argv[3]);
        std::vector<uint8_t> psB; if (!noPS) psB = readFile(argv[4]);
        if (vsB.empty() || hsB.empty() || dsB.empty() || (!noPS && psB.empty())) { printf("FAIL read inputs\n"); return 1; }

        IRCompiler* comp = IRCompilerCreate();
        IRCompilerSetMinimumGPUFamily(comp, IRGPUFamilyMetal3);
        IRCompilerEnableGeometryAndTessellationEmulation(comp, true);
        IRCompilerSetStageInGenerationMode(comp, IRStageInCodeGenerationModeUseSeparateStageInFunction);
        IRCompilerSetGlobalRootSignature(comp, nullptr);

        // ---- Vertex stage + stage-in
        IRObject* vs = compile(comp, vsB, "VS"); if (!vs) return 1;
        IRShaderReflection* vsRefl = IRShaderReflectionCreate();
        IRObjectGetReflection(vs, IRShaderStageVertex, vsRefl);
        IRVersionedVSInfo vsInfo = {}; vsInfo.version = IRReflectionVersion_1_0;
        IRShaderReflectionCopyVertexInfo(vsRefl, IRReflectionVersion_1_0, &vsInfo);
        printf("VS: entry=%s vsOutputSize=%u inputs=%zu\n", IRShaderReflectionGetEntryPointFunctionName(vsRefl),
               vsInfo.info_1_0.vertex_output_size_in_bytes, vsInfo.info_1_0.num_vertex_inputs);

        IRVersionedInputLayoutDescriptor layout = {}; layout.version = IRInputLayoutDescriptorVersion_1;
        auto vsIn = parseSig(vsB, "ISG1");
        std::vector<std::string> names; uint32_t offset = 0, n = 0;
        for (auto& s : vsIn) if (s.sysval == 0) names.push_back(s.name);
        for (auto& s : vsIn) {
            if (s.sysval != 0) continue;
            uint32_t sz; IRFormat fmt = formatFor(&s == &vsIn[0] ? s : s, &sz);
            layout.desc_1_0.semanticNames[n] = names[n].c_str();
            layout.desc_1_0.inputElementDescs[n] = { s.idx, fmt, 0, offset, 0, IRInputClassificationPerVertexData };
            printf("  layout[%u] %s%u fmt=%d off=%u\n", n, s.name.c_str(), s.idx, (int)fmt, offset);
            offset += sz; n++;
        }
        layout.desc_1_0.numElements = n;
        IRMetalLibBinary* stageInBin = IRMetalLibBinaryCreate();
        if (!IRMetalLibSynthesizeStageInFunction(comp, vsRefl, &layout, stageInBin)) { printf("FAIL synthesize stage-in\n"); return 1; }
        IRMetalLibBinary* vsBin = IRMetalLibBinaryCreate();
        if (!IRObjectGetMetalLibBinary(vs, IRShaderStageVertex, vsBin)) { printf("FAIL get VS metallib\n"); return 1; }

        // ---- Hull
        IRObject* hs = compile(comp, hsB, "HS"); if (!hs) return 1;
        IRShaderReflection* hsRefl = IRShaderReflectionCreate();
        IRObjectGetReflection(hs, IRShaderStageHull, hsRefl);
        IRVersionedHSInfo hsInfo = {}; hsInfo.version = IRReflectionVersion_1_0;
        IRShaderReflectionCopyHullInfo(hsRefl, IRReflectionVersion_1_0, &hsInfo);
        IRMetalLibBinary* hsBin = IRMetalLibBinaryCreate();
        if (!IRObjectGetMetalLibBinary(hs, IRShaderStageHull, hsBin)) { printf("FAIL get HS metallib\n"); return 1; }
        printf("HS: inCP=%u outCP=%u outCPsize=%u patchConst=%u maxPatches/tg=%u objThreads/patch=%u maxTess=%g outPrim=%d\n",
               hsInfo.info_1_0.input_control_point_count, hsInfo.info_1_0.output_control_point_count, hsInfo.info_1_0.output_control_point_size,
               hsInfo.info_1_0.patch_constants_size, hsInfo.info_1_0.max_patches_per_object_threadgroup, hsInfo.info_1_0.max_object_threads_per_patch,
               hsInfo.info_1_0.max_tessellation_factor, (int)hsInfo.info_1_0.tessellator_output_primitive);

        // ---- Domain
        IRObject* ds = compile(comp, dsB, "DS"); if (!ds) return 1;
        IRShaderReflection* dsRefl = IRShaderReflectionCreate();
        IRObjectGetReflection(ds, IRShaderStageDomain, dsRefl);
        IRVersionedDSInfo dsInfo = {}; dsInfo.version = IRReflectionVersion_1_0;
        IRShaderReflectionCopyDomainInfo(dsRefl, IRReflectionVersion_1_0, &dsInfo);
        IRMetalLibBinary* dsBin = IRMetalLibBinaryCreate();
        if (!IRObjectGetMetalLibBinary(ds, IRShaderStageDomain, dsBin)) { printf("FAIL get DS metallib\n"); return 1; }
        printf("DS: inCP=%u inCPsize=%u patchConst=%u maxPrims/meshTg=%u\n", dsInfo.info_1_0.input_control_point_count,
               dsInfo.info_1_0.input_control_point_size, dsInfo.info_1_0.patch_constants_size, dsInfo.info_1_0.max_input_prims_per_mesh_threadgroup);

        // ---- Pixel
        IRMetalLibBinary* psBin = nullptr; std::string psEntry;
        if (!noPS) {
            IRObject* ps = compile(comp, psB, "PS"); if (!ps) return 1;
            IRShaderReflection* psRefl = IRShaderReflectionCreate();
            IRObjectGetReflection(ps, IRShaderStageFragment, psRefl);
            psBin = IRMetalLibBinaryCreate();
            if (!IRObjectGetMetalLibBinary(ps, IRShaderStageFragment, psBin)) { printf("FAIL get PS metallib\n"); return 1; }
            psEntry = IRShaderReflectionGetEntryPointFunctionName(psRefl);
            printf("PS: entry=%s\n", psEntry.c_str());
        } else printf("PS: none (depth-only pipeline)\n");

        bool valid = IRRuntimeValidateTessellationPipeline((IRRuntimeTessellatorOutputPrimitive)hsInfo.info_1_0.tessellator_output_primitive, IRRuntimePrimitiveTypeTriangle,
            hsInfo.info_1_0.output_control_point_size, dsInfo.info_1_0.input_control_point_size,
            hsInfo.info_1_0.patch_constants_size, dsInfo.info_1_0.patch_constants_size,
            hsInfo.info_1_0.output_control_point_count, dsInfo.info_1_0.input_control_point_count);
        printf("IRRuntimeValidateTessellationPipeline: %s\n", valid ? "ok" : "MISMATCH");

        id<MTLLibrary> stageInLib = makeLib(dev, stageInBin, "stage-in", dumpDir, "stagein.metallib");
        id<MTLLibrary> vsLib = makeLib(dev, vsBin, "VS", dumpDir, "vs.metallib");
        id<MTLLibrary> hsLib = makeLib(dev, hsBin, "HS", dumpDir, "hs.metallib");
        id<MTLLibrary> dsLib = makeLib(dev, dsBin, "DS", dumpDir, "ds.metallib");
        id<MTLLibrary> psLib = noPS ? nil : makeLib(dev, psBin, "PS", dumpDir, "ps.metallib");
        if (!stageInLib || !vsLib || !hsLib || !dsLib || (!noPS && !psLib)) return 1;
        printf("libs: stagein=%s vs=%s hs=%s ds=%s\n", [stageInLib.functionNames componentsJoinedByString:@","].UTF8String,
               [vsLib.functionNames componentsJoinedByString:@","].UTF8String, [hsLib.functionNames componentsJoinedByString:@","].UTF8String,
               [dsLib.functionNames componentsJoinedByString:@","].UTF8String);

        MTLMeshRenderPipelineDescriptor* base = [MTLMeshRenderPipelineDescriptor new];
        auto psOut = noPS ? std::vector<SigElem>{} : parseSig(psB, "OSG1");
        int targets = 0;
        for (auto& s : psOut) {
            if (s.name == "SV_Target") {
                base.colorAttachments[s.idx].pixelFormat = s.comp == 3 ? MTLPixelFormatRGBA16Float : s.comp == 1 ? MTLPixelFormatRGBA32Uint : MTLPixelFormatRGBA32Sint;
                targets++;
            } else if (s.name == "SV_Depth" || s.name == "SV_DepthLessEqual" || s.name == "SV_DepthGreaterEqual") {
                base.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
            }
        }
        if (base.depthAttachmentPixelFormat == MTLPixelFormatInvalid) base.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        printf("PS targets=%d\n", targets);

        IRGeometryTessellationEmulationPipelineDescriptor desc = {};
        desc.stageInLibrary = stageInLib;
        desc.vertexLibrary = vsLib;
        desc.vertexFunctionName = IRShaderReflectionGetEntryPointFunctionName(vsRefl);
        desc.hullLibrary = hsLib; desc.hullFunctionName = "irconverter_hull_shader";
        desc.domainLibrary = dsLib; desc.domainFunctionName = "irconverter_dxil_domain_shader";
        desc.geometryLibrary = nil; desc.geometryFunctionName = kIRTrianglePassthroughGeometryShader;
        desc.fragmentLibrary = psLib; desc.fragmentFunctionName = psEntry.c_str();
        desc.basePipelineDescriptor = base;
        desc.pipelineConfig.outputPrimitiveType = (IRRuntimeTessellatorOutputPrimitive)hsInfo.info_1_0.tessellator_output_primitive;
        desc.pipelineConfig.vsOutputSizeInBytes = vsInfo.info_1_0.vertex_output_size_in_bytes;
        desc.pipelineConfig.gsMaxInputPrimitivesPerMeshThreadgroup = dsInfo.info_1_0.max_input_prims_per_mesh_threadgroup;
        desc.pipelineConfig.hsMaxPatchesPerObjectThreadgroup = hsInfo.info_1_0.max_patches_per_object_threadgroup;
        desc.pipelineConfig.hsInputControlPointCount = hsInfo.info_1_0.input_control_point_count;
        desc.pipelineConfig.hsMaxObjectThreadsPerThreadgroup = hsInfo.info_1_0.max_object_threads_per_patch;
        desc.pipelineConfig.hsMaxTessellationFactor = hsInfo.info_1_0.max_tessellation_factor;
        desc.pipelineConfig.gsInstanceCount = 1;

        NSError* err = nil;
        id<MTLRenderPipelineState> pso = nil;
        {
            id<MTLFunction> stageInFn = [stageInLib newFunctionWithName:@"irconverter_stage_in_shader"];
            id<MTLFunction> fragFn = noPS ? nil : [psLib newFunctionWithName:[NSString stringWithUTF8String:psEntry.c_str()]];
            id<MTLFunction> domainFn = [dsLib newFunctionWithName:@"irconverter_dxil_domain_shader"];
            bool tessOn = true;
            MTLFunctionConstantValues* vcv = [MTLFunctionConstantValues new];
            [vcv setConstantValue:&tessOn type:MTLDataTypeBool withName:@"tessellationEnabled"];
            MTLFunctionDescriptor* fd = [MTLFunctionDescriptor new]; fd.constantValues = vcv;
            fd.name = [NSString stringWithFormat:@"%s.dxil_irconverter_object_shader", desc.vertexFunctionName];
            id<MTLFunction> vertexFn = [vsLib newFunctionWithDescriptor:fd error:&err];
            if (!vertexFn) { printf("FAIL vertex object fn: %s\n", err.localizedDescription.UTF8String); return 1; }
            MTLFunctionConstantValues* hcv = [MTLFunctionConstantValues new];
            [hcv setConstantValue:&desc.pipelineConfig.vsOutputSizeInBytes type:MTLDataTypeInt withName:@"vertex_shader_output_size_fc"];
            [hcv setConstantValue:&desc.pipelineConfig.hsMaxTessellationFactor type:MTLDataTypeFloat withName:@"max_tessellation_factor_fc"];
            fd = [MTLFunctionDescriptor new]; fd.constantValues = hcv; fd.name = @"irconverter_hull_shader";
            id<MTLFunction> hullFn = [hsLib newFunctionWithDescriptor:fd error:&err];
            if (!hullFn) { printf("FAIL hull fn: %s\n", err.localizedDescription.UTF8String); return 1; }
            fd.name = @"irconverter_tessellator";
            id<MTLFunction> tessFn = [hsLib newFunctionWithDescriptor:fd error:&err];
            if (!tessFn) { printf("FAIL tessellator fn: %s\n", err.localizedDescription.UTF8String); return 1; }
            id<MTLFunction> geomFn = [dsLib newFunctionWithName:[NSString stringWithUTF8String:desc.geometryFunctionName]];
            if (!stageInFn || !domainFn || !geomFn || (!noPS && !fragFn)) { printf("FAIL function lookup (stagein=%d domain=%d geom=%d frag=%d)\n", !!stageInFn, !!domainFn, !!geomFn, !!fragFn); return 1; }
            base.objectFunction = vertexFn; base.meshFunction = geomFn; base.fragmentFunction = fragFn;
            MTLLinkedFunctions* ol = [MTLLinkedFunctions new]; ol.functions = @[stageInFn, hullFn]; base.objectLinkedFunctions = ol;
            MTLLinkedFunctions* ml = [MTLLinkedFunctions new]; ml.functions = @[tessFn, domainFn]; base.meshLinkedFunctions = ml;
            if (!useMtl4) {
                pso = [dev newRenderPipelineStateWithMeshDescriptor:base options:MTLPipelineOptionNone reflection:nil error:&err];
            } else {
                // Metal 4 path: same functions, built through MTL4Compiler (what D3DMetal uses under D3DM_MTL4=1).
                auto libFn = ^MTL4FunctionDescriptor*(id<MTLLibrary> lib, NSString* name, MTLFunctionConstantValues* cv) {
                    MTL4LibraryFunctionDescriptor* lf = [MTL4LibraryFunctionDescriptor new]; lf.library = lib; lf.name = name;
                    if (!cv) return lf;
                    MTL4SpecializedFunctionDescriptor* sf = [MTL4SpecializedFunctionDescriptor new]; sf.functionDescriptor = lf; sf.constantValues = cv;
                    return sf;
                };
                MTL4MeshRenderPipelineDescriptor* d4 = [MTL4MeshRenderPipelineDescriptor new];
                d4.objectFunctionDescriptor = libFn(vsLib, [NSString stringWithFormat:@"%s.dxil_irconverter_object_shader", desc.vertexFunctionName], vcv);
                d4.meshFunctionDescriptor = libFn(dsLib, [NSString stringWithUTF8String:desc.geometryFunctionName], nil);
                d4.fragmentFunctionDescriptor = noPS ? nil : libFn(psLib, [NSString stringWithUTF8String:psEntry.c_str()], nil);
                d4.objectStaticLinkingDescriptor.functionDescriptors = @[ libFn(stageInLib, @"irconverter_stage_in_shader", nil), libFn(hsLib, @"irconverter_hull_shader", hcv) ];
                d4.meshStaticLinkingDescriptor.functionDescriptors = @[ libFn(hsLib, @"irconverter_tessellator", hcv), libFn(dsLib, @"irconverter_dxil_domain_shader", nil) ];
                for (int i = 0; i < 8; i++) d4.colorAttachments[i].pixelFormat = base.colorAttachments[i].pixelFormat;
                if (noPS) d4.rasterizationEnabled = YES;
                id<MTL4Compiler> c4 = [dev newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&err];
                if (!c4) { printf("PIPELINE FAIL: no MTL4Compiler: %s\n", err.localizedDescription.UTF8String); return 1; }
                pso = [c4 newRenderPipelineStateWithDescriptor:d4 compilerTaskOptions:nil error:&err];
                if (pso) printf("(built via MTL4Compiler)\n");
            }
        }
        if (pso) {
            printf("PIPELINE OK  (%s)\n", pso.label ? pso.label.UTF8String : "mesh pipeline");
        } else {
            printf("PIPELINE FAIL: %s\n", err ? err.localizedDescription.UTF8String : "(no NSError: a function lookup returned nil before pipeline creation)");
            if (err && err.userInfo) printf("  userInfo: %s\n", err.userInfo.description.UTF8String);
            return 1;
        }
        return 0;
    }
}
