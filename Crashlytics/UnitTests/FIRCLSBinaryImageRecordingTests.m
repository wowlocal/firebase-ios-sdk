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



// MARK: -

#include "Crashlytics/Crashlytics/Components/FIRCLSContext.h"
#import "Crashlytics/Crashlytics/Controllers/FIRCLSManagerData.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSExecutionIdentifierModel.h"
#import "Crashlytics/Crashlytics/Models/FIRCLSInternalReport.h"
#import "Crashlytics/Crashlytics/Private/FIRCLSOnDemandModel_Private.h"
#import "Crashlytics/UnitTests/Mocks/FIRAppFake.h"
#import "Crashlytics/UnitTests/Mocks/FIRCLSMockExistingReportManager.h"
#import "Crashlytics/UnitTests/Mocks/FIRCLSMockOnDemandModel.h"
#import "Crashlytics/UnitTests/Mocks/FIRCLSMockReportUploader.h"
#import "Crashlytics/UnitTests/Mocks/FIRCLSMockSettings.h"
#import "Crashlytics/UnitTests/Mocks/FIRCLSTempMockFileManager.h"
#import "Crashlytics/UnitTests/Mocks/FIRMockGDTCoreTransport.h"
#import "Crashlytics/UnitTests/Mocks/FIRMockInstallations.h"

#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionArbiter.h"
#import "Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionToken.h"
#import "Crashlytics/Crashlytics/Settings/Models/FIRCLSApplicationIdentifierModel.h"

#define TEST_GOOGLE_APP_ID (@"1:632950151350:ios:d5b0d08d4f00f4b1")


// MARK: -

#include <mach-o/dyld.h>
#include <dlfcn.h>

#import "Crashlytics/Crashlytics/Models/FIRCLSInternalReport.h"

@interface FIRCLSBinaryImageRecordingTests : XCTestCase

@property(strong) NSString *resourcePath;




// MARK: -

@property(nonatomic, retain) FIRCLSMockOnDemandModel *onDemandModel;
@property(nonatomic, strong) FIRCLSExistingReportManager *existingReportManager;
@property(nonatomic, strong) FIRCLSManagerData *managerData;
@property(nonatomic, strong) FIRCLSDataCollectionArbiter *dataArbiter;
@property(nonatomic, strong) FIRCLSTempMockFileManager *fileManager;
@property(nonatomic, strong) FIRCLSMockReportUploader *mockReportUploader;
@property(nonatomic, strong) FIRCLSMockSettings *mockSettings;

@property(nonatomic, strong) NSString *reportPath;

// MARK: -

@end

@implementation FIRCLSBinaryImageRecordingTests

- (void)setUp {
  [super setUp];

  self.resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
  XCTAssertNotNil(self.resourcePath);

  // we need to FIRCLSFileInitWithPath(Mode) or FIRCLSContextInitialize?
  // FIRCLSContextInitialize has metadata initialization logic
//  FIRCLSContextBaseInit(); // do it once
  [self initContextOnce];
}

- (NSString *)pathToFileNamed:(NSString *)name {
  NSString *path = [[self resourcePath] stringByAppendingPathComponent:name];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
  return path;
}

- (void)initContextOnce {

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    FIRSetLoggerLevel(FIRLoggerLevelMax);

    FIRCLSContextBaseInit();

    id fakeApp = [[FIRAppFake alloc] init];
    self.dataArbiter = [[FIRCLSDataCollectionArbiter alloc] initWithApp:fakeApp withAppInfo:@{}];

    self.fileManager = [[FIRCLSTempMockFileManager alloc] init];

    FIRCLSApplicationIdentifierModel *appIDModel = [[FIRCLSApplicationIdentifierModel alloc] init];
    _mockSettings = [[FIRCLSMockSettings alloc] initWithFileManager:self.fileManager
                                                         appIDModel:appIDModel];
    _onDemandModel = [[FIRCLSMockOnDemandModel alloc] initWithFIRCLSSettings:_mockSettings
                                                                  sleepBlock:^(int delay){
    }];

    FIRMockInstallations *iid = [[FIRMockInstallations alloc] initWithFID:@"test_token"];

    FIRMockGDTCORTransport *mockGoogleTransport =
    [[FIRMockGDTCORTransport alloc] initWithMappingID:@"id" transformers:nil target:0];

    _managerData = [[FIRCLSManagerData alloc] initWithGoogleAppID:TEST_GOOGLE_APP_ID
                                                  googleTransport:mockGoogleTransport
                                                    installations:iid
                                                        analytics:nil
                                                      fileManager:self.fileManager
                                                      dataArbiter:self.dataArbiter
                                                         settings:self.mockSettings
                                                    onDemandModel:_onDemandModel];
    _mockReportUploader = [[FIRCLSMockReportUploader alloc] initWithManagerData:self.managerData];
    _existingReportManager =
    [[FIRCLSExistingReportManager alloc] initWithManagerData:self.managerData
                                              reportUploader:self.mockReportUploader];
    [self.fileManager createReportDirectories];
    [self.fileManager
     setupNewPathForExecutionIdentifier:self.managerData.executionIDModel.executionID];

    NSString *name = @"exception_model_report";
    self.reportPath = [self.fileManager.rootPath stringByAppendingPathComponent:name];
    [self.fileManager createDirectoryAtPath:self.reportPath];

    FIRCLSInternalReport *report =
    [[FIRCLSInternalReport alloc] initWithPath:self.reportPath
                           executionIdentifier:@"TEST_EXECUTION_IDENTIFIER"];
    FIRCLSContextInitialize(report, self.mockSettings, self.fileManager); //#1
  });
}

- (void)testFileBinaryImageStore {
//  NSString *imageStorePath = [self.reportPath stringByAppendingPathComponent:FIRCLSReportBinaryImageFile];
//  XCTAssertTrue(strcmp(imageStorePath.fileSystemRepresentation,
//                       _firclsContext.readonly->binaryimage.path) == 0);
//
//  NSString *dylibPath = [self pathToFileNamed:@"empty_func.dylib"]; //[self pathToFileNamed:@"empty.dylib"];
//  void *handle = dlopen(dylibPath.fileSystemRepresentation, RTLD_NOW);
//  XCTAssertTrue(handle != NULL);
//  __auto_type getRecords = ^NSArray<NSString *> *(void) {
//    return [[NSString stringWithContentsOfFile:imageStorePath
//                                      encoding:NSUTF8StringEncoding
//                                         error:NULL]
//            componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
//  };
//
//  __block NSString *imageInfoString = nil;
//
//  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
//    FIRCLSFileFlushWriteBuffer(&_firclsContext.writable->binaryImage.file);
//    __block NSRange dylibRecordPrefix = NSMakeRange(NSNotFound, 0);
//    [getRecords() enumerateObjectsUsingBlock:^(NSString *record, NSUInteger idx, BOOL *stop) {
//      dylibRecordPrefix = [record rangeOfString:[NSString stringWithFormat:@"{\"load\":{\"path\":\"%@\",", dylibPath]];
//      if (dylibRecordPrefix.location != NSNotFound) {
//        *stop = true;
//        imageInfoString = [record substringWithRange:NSMakeRange(dylibRecordPrefix.length, record.length - dylibRecordPrefix.length)];
//      }
//    }];
//    XCTAssertTrue(dylibRecordPrefix.location != NSNotFound, @"%@ does not contain information about loaded dylib", imageStorePath);
//    XCTAssertTrue(dylibRecordPrefix.location == 0, @"clsrecord format error");
//  });
//
//  dlclose(handle);
//
//  dispatch_sync(FIRCLSGetBinaryImageQueue(), ^{
//    FIRCLSFileFlushWriteBuffer(&_firclsContext.writable->binaryImage.file);
//    __block bool containsUnloadRecord = false;
//    [getRecords() enumerateObjectsUsingBlock:^(NSString *record, NSUInteger idx, BOOL *stop) {
//      if ([record hasPrefix:@"{\"unload\":{\"path\":null,"]) {
//        containsUnloadRecord = [record hasSuffix:imageInfoString];
//        if (containsUnloadRecord) *stop = true;
//      }
//    }];
//    XCTAssertTrue(containsUnloadRecord, @"%@ does not contain information about unloaded dylib", imageStorePath);
//  });
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
