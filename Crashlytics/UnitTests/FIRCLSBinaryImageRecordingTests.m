// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <XCTest/XCTest.h>

#import "Crashlytics/Crashlytics/Components/FIRCLSBinaryImage.h"
#import "Crashlytics/Crashlytics/Components/FIRCLSGlobals.h"

#include <mach-o/dyld.h>
#include <dlfcn.h>

@interface FIRCLSBinaryImageRecordingTests : XCTestCase

@property(strong) NSString *resourcePath;

@end

@implementation FIRCLSBinaryImageRecordingTests

- (void)setUp {
  [super setUp];

  self.resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
  XCTAssertNotNil(self.resourcePath);

  FIRCLSContextBaseInit();
}

- (void)tearDown {
  FIRCLSContextBaseDeinit();

  [super tearDown];
}

- (NSString *)pathToFileNamed:(NSString *)name {
  NSString *path = [[self resourcePath] stringByAppendingPathComponent:name];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
  return path;
}

- (void)testExample {
  FIRCLSBinaryImageInit();

  const char *lib_path = [[self pathToFileNamed:@"empty_func.dylib"] cStringUsingEncoding:NSASCIIStringEncoding];
  void *handle = dlopen(lib_path, RTLD_NOW);
                        //RTLD_FIRST);
  XCTAssertTrue(handle != NULL);

- (void)testFileBinaryImageStore {
  NSString *imageStorePath = [self.reportPath stringByAppendingPathComponent:FIRCLSReportBinaryImageFile];
  XCTAssertTrue(strcmp(imageStorePath.fileSystemRepresentation,
                       _firclsContext.readonly->binaryimage.path) == 0);

  NSString *dylibPath = [self pathToFileNamed:@"empty_func.dylib"]; //[self pathToFileNamed:@"empty_func2.dylib"];
  void *handle = dlopen(dylibPath.fileSystemRepresentation, RTLD_NOW);
  XCTAssertTrue(handle != NULL);
  __auto_type getRecords = ^NSArray<NSString *> *(void) {
    return [[NSString stringWithContentsOfFile:imageStorePath
                                      encoding:NSUTF8StringEncoding
                                         error:NULL]
            componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  };

  __block NSString *imageInfoString = nil;

  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
    __block NSRange dylibRecordPrefix = NSMakeRange(NSNotFound, 0);
    [getRecords() enumerateObjectsUsingBlock:^(NSString *record, NSUInteger idx, BOOL *stop) {
      dylibRecordPrefix = [record rangeOfString:[NSString stringWithFormat:@"{\"load\":{\"path\":\"%@\",", dylibPath]];
      if (dylibRecordPrefix.location != NSNotFound) {
        *stop = true;
        imageInfoString = [record substringWithRange:NSMakeRange(dylibRecordPrefix.length, record.length - dylibRecordPrefix.length)];
      }
    }];
    XCTAssertTrue(dylibRecordPrefix.location != NSNotFound, @"%@ does not contain information about loaded dylib", imageStorePath);
    XCTAssertTrue(dylibRecordPrefix.location == 0, @"clsrecord format error");
  });

  dlclose(handle);

  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
    __block bool containsUnloadRecord = false;
    [getRecords() enumerateObjectsUsingBlock:^(NSString *record, NSUInteger idx, BOOL *stop) {
      if ([record hasPrefix:@"{\"unload\":{\"path\":null,"]) {
        containsUnloadRecord = [record hasSuffix:imageInfoString];
        if (containsUnloadRecord) *stop = true;
      }
    }];
    XCTAssertTrue(containsUnloadRecord, @"%@ does not contain information about unloaded dylib", imageStorePath);
  });
}

- (void)testInMemoryBinaryImageStore {
  NSString *dylibPath = [self pathToFileNamed:@"empty_func.dylib"];
  // 0. register _dyld_register_func_for_add_image
  // then capture all values and compare with imageDetails
  void *handle = dlopen(dylibPath.fileSystemRepresentation, RTLD_NOW);
  XCTAssertTrue(handle != NULL);

  __block void *dylibStartAddress;

  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
    void* sym = dlsym(handle, "empty");
    XCTAssertTrue(sym != NULL, @"%s", dlerror());

    Dl_info image_info;
    memset(&image_info, 0, sizeof(Dl_info));
    dladdr(sym, &image_info);
    dylibStartAddress = image_info.dli_fbase;

    bool found = false;
    for (int i = 0; i < CLS_BINARY_IMAGE_RUNTIME_NODE_COUNT; ++i) {
      FIRCLSBinaryImageRuntimeNode node = _firclsContext.writable->binaryImage.nodes[i];
      if (dylibStartAddress == node.baseAddress) {
        found = true;
        XCTAssertTrue(
                      node.size != 0 &
                      node.unwindInfo != NULL
                      );
        break;
      }
    }
    XCTAssertTrue(found, @"dylib not found in the In-Memory Storage");
  });

  dlclose(handle);

  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
    bool found = false;
    for (int i = 0; i < CLS_BINARY_IMAGE_RUNTIME_NODE_COUNT; ++i) {
      FIRCLSBinaryImageRuntimeNode node = _firclsContext.writable->binaryImage.nodes[i];
      if (dylibStartAddress == node.baseAddress) {
        found = true;
        XCTAssertTrue(
                      node.size == 0 &
                      node.unwindInfo == NULL
                      );
        break;
      }
    }
    XCTAssertTrue(found, @"dylib %@ must persist after unloading the dylib", dylibPath);
  });
}

@end
