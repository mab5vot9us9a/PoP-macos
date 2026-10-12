// Load metallibs and force backend compilation of every function.
// Hull functions get their function constants (vertex_shader_output_size_fc,
// max_tessellation_factor_fc) specialised, mirroring what the IR runtime does.
// Build: clang++ -std=c++17 -fobjc-arc -framework Metal -framework Foundation load_metallib.mm -o load_metallib
// Usage: ./load_metallib [--vsout N] [--maxtess F] file.metallib...
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstring>

int main(int argc, char** argv) {
    @autoreleasepool {
        int vsOut = 64; float maxTess = 64.0f;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        printf("device: %s\n", dev.name.UTF8String);
        int fails = 0;
        for (int i = 1; i < argc; i++) {
            if (!strcmp(argv[i], "--vsout")) { vsOut = atoi(argv[++i]); continue; }
            if (!strcmp(argv[i], "--maxtess")) { maxTess = atof(argv[++i]); continue; }
            NSString* path = [NSString stringWithUTF8String:argv[i]];
            NSError* err = nil;
            NSData* data = [NSData dataWithContentsOfFile:path];
            if (!data) { printf("FAIL read %s\n", argv[i]); fails++; continue; }
            dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, nullptr, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            id<MTLLibrary> lib = [dev newLibraryWithData:dd error:&err];
            if (!lib) { printf("FAIL newLibrary %s: %s\n", argv[i], err.localizedDescription.UTF8String); fails++; continue; }
            for (NSString* fn in lib.functionNames) {
                MTLFunctionConstantValues* cv = [MTLFunctionConstantValues new];
                NSDictionary* consts = nil;
                @try {
                    id<MTLFunction> probe = [lib newFunctionWithName:fn];
                    consts = probe ? probe.functionConstantsDictionary : nil;
                } @catch (NSException* e) {}
                BOOL needConst = NO;
                for (NSString* cname in consts) {
                    MTLFunctionConstant* c = consts[cname];
                    needConst = YES;
                    if ([cname isEqualToString:@"vertex_shader_output_size_fc"]) [cv setConstantValue:&vsOut type:MTLDataTypeInt withName:cname];
                    else if ([cname isEqualToString:@"max_tessellation_factor_fc"]) [cv setConstantValue:&maxTess type:MTLDataTypeFloat withName:cname];
                    else {
                        // generic zero of the right type
                        char zero[64] = {0}; float one = 1.0f;
                        if (c.type == MTLDataTypeFloat) [cv setConstantValue:&one type:c.type withName:cname];
                        else [cv setConstantValue:zero type:c.type withName:cname];
                    }
                }
                err = nil;
                id<MTLFunction> f = needConst ? [lib newFunctionWithName:fn constantValues:cv error:&err]
                                              : [lib newFunctionWithName:fn];
                const char* typeName = "?";
                if (f) switch (f.functionType) {
                    case MTLFunctionTypeVertex: typeName = "vertex"; break;
                    case MTLFunctionTypeFragment: typeName = "fragment"; break;
                    case MTLFunctionTypeKernel: typeName = "kernel"; break;
                    case MTLFunctionTypeVisible: typeName = "visible"; break;
                    case MTLFunctionTypeIntersection: typeName = "intersection"; break;
                    case MTLFunctionTypeMesh: typeName = "mesh"; break;
                    case MTLFunctionTypeObject: typeName = "object"; break;
                    default: break;
                }
                if (f) {
                    printf("OK   %s :: %s (%s", path.lastPathComponent.UTF8String, fn.UTF8String, typeName);
                    for (NSString* cname in consts) printf(" %s", cname.UTF8String);
                    printf(")\n");
                } else {
                    printf("FAIL %s :: %s : %s\n", path.lastPathComponent.UTF8String, fn.UTF8String,
                           err ? err.localizedDescription.UTF8String : "(nil, no error)");
                    fails++;
                }
            }
        }
        printf("failures: %d\n", fails);
        return fails ? 1 : 0;
    }
}
