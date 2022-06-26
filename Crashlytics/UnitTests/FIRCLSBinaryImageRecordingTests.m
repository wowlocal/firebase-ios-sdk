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

  void *handle = dlopen(
                        [self pathToFileNamed:@"empty_func.dylib"].cString,
                        //[self pathToFileNamed:@"test_ios_framework.framework/test_ios_framework"].cString,
                        RTLD_NOW);
                        //RTLD_FIRST);
  __auto_type context = _firclsContext;

  char *err = dlerror();

  // TODO: check context->writable.binaryImage.file content
  // TODO: _firclsContext.writable->binaryImage.nodes content
  void* sym = dlsym(handle, "foo");
//
//  Dl_info dlInfo;
//  int retval = dladdr(sym, &dlInfo);

//  sleep(1);
  //  dlopen
  // wait until the recording is finished
  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{});
}

- (void)testAnother {
  // check number fileed nodes
//  FIRCLSBinaryImageInit(); // dispatch once for tests?

  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{});
}

@end
