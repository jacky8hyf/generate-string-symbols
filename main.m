//
//  main.m
//  generate-string-symbols
//
//  Created by Daniel Kennett on 07/08/14.
//  For license information, see LICENSE.markdown

#import <Foundation/Foundation.h>

#pragma mark - Helper functions

void printUsage() {

    NSString *processName = [[NSProcessInfo processInfo] processName];

    printf("%s by Daniel Kennett\n\n", processName.UTF8String);

    printf("Outputs a header file containing symbols for the given .strings\n");
    printf("file's keys.\n\n");

    printf("Usage: %s -strings <strings file path>\n", processName.UTF8String);
    printf("       %s -out <output file path> \n\n", [@"" stringByPaddingToLength:processName.length
                                                                     withString:@" "
                                                                startingAtIndex:0].UTF8String);

    printf("  -strings  The path to a valid .strings file.\n\n");

    printf("  -out      The path to write the output header file to. Missing\n");
    printf("            directories will be created along the way. If a file\n");
    printf("            already exists at the given path, it will be\n");
    printf("            overwritten. If not specified, result will output to \n");
    printf("            standard out.");

    printf("\n\n");
}

NS_INLINE NSString *replaceRegex(NSString *original, NSString *pattern, NSString *replacementTemplate) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    
    NSRange stringRange = NSMakeRange(0, original.length);
    return [regex stringByReplacingMatchesInString:original options:NSMatchingReportProgress range:stringRange withTemplate:replacementTemplate];
    
}

NS_INLINE NSString *sanitizeToken(NSString *token) {
    NSMutableString *ret = [NSMutableString stringWithString:token];
    NSDictionary *symbolsLookup = @{@"?":@"QuestionMark",
                                    @":":@"Colon",
                                    @";":@"Semicolon",
                                    @",":@"Comma",
                                    @".":@"Period",
                                    @"'":@"Quote",
                                    @"\"":@"DoubleQuote"};
    [symbolsLookup enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * obj, BOOL *stop) {
        [ret replaceOccurrencesOfString:key withString:obj options:0 range:NSMakeRange(0, ret.length)];
    }];
    NSString *ret2 = replaceRegex(ret, @"[^a-zA-Z0-9]", @"_");
    return ret2;
}

NS_INLINE NSString *sanitize(NSString *key) {
    NSArray *tokens = [key componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableString *str = [NSMutableString string];
    for(NSString *token in tokens) {
        [str appendString:sanitizeToken(token)];
    }
    return str;
}

NS_INLINE NSString *padLeft(NSString *str, NSUInteger maxLength) {
    if(str.length >= maxLength)
        return str;
    NSUInteger spacesNeeded = maxLength - str.length;
    return [NSString stringWithFormat:@"%@%*s", str, (int)spacesNeeded, ""];
}

// http://blog.hozbox.com/2012/01/03/escaping-all-control-characters-in-a-nsstring/
NS_INLINE NSString *repr(NSString *str) {
    NSMutableString *myRepr = [[NSMutableString alloc] initWithString:str];
    NSRange myRange = NSMakeRange(0, [str length]);
    NSArray *toReplace = [NSArray arrayWithObjects:@"\0", @"\a", @"\b", @"\t", @"\n", @"\f", @"\r", @"\e", nil];
    NSArray *replaceWith = [NSArray arrayWithObjects:@"\\0", @"\\a", @"\\b", @"\\t", @"\\n", @"\\f", @"\\r", @"\\e", nil];
    for (NSUInteger i = 0, count = [toReplace count]; i < count; ++i) {
        [myRepr replaceOccurrencesOfString:[toReplace objectAtIndex:i] withString:[replaceWith objectAtIndex:i] options:0 range:myRange];
    }
    NSString *retStr = [NSString stringWithFormat:@"\"%@\"", myRepr];
    return retStr;
}

#pragma mark - Main

int main(int argc, const char * argv[])
{

    @autoreleasepool {
        for (int i = 0; i < argc; i++) {
            const char *c = argv[i];
            if(strcmp(c, "-h") == 0 || strcmp(c, "--help") == 0) {
                printUsage();
                exit(EXIT_SUCCESS);
            }
        }

        NSString *inputFilePath = [[NSUserDefaults standardUserDefaults] valueForKey:@"strings"];
        NSString *outputFilePath = [[NSUserDefaults standardUserDefaults] valueForKey:@"out"];

        setbuf(stdout, NULL);
        
        NSError *error = nil;
        NSData *plistData;
        if(inputFilePath.length != 0) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:inputFilePath]) {
                printf("ERROR: Input file %s doesn't exist.\n", [inputFilePath UTF8String]);
                exit(EXIT_FAILURE);
            }
            
            plistData = [NSData dataWithContentsOfFile:inputFilePath
                                                       options:0
                                                         error:&error];
            
            if (error != nil) {
                printf("ERROR: Reading input file failed with error: %s\n", error.localizedDescription.UTF8String);
                exit(EXIT_FAILURE);
            }
        } else {
            NSMutableData *data = [NSMutableData data];
            ssize_t n;
            char buf[4096];
            while((n = read(0,buf,sizeof(buf))) != 0){
                [data appendBytes:buf length:n];
            }
            plistData = data;
        }

        id plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                             options:0
                                                              format:nil
                                                               error:&error];

        if (error != nil) {
            printf("ERROR: Reading input file failed with error: %s\n", error.localizedDescription.UTF8String);
            exit(EXIT_FAILURE);
        }

        if (![plist isKindOfClass:[NSDictionary class]]) {
            printf("ERROR: Strings file contained unexpected root object type.");
            exit(EXIT_FAILURE);
        }

        NSMutableString *fileContents = [NSMutableString new];

        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss ZZZZZ";

        [fileContents appendFormat:@"// Generated by %@ on %@\n", [[NSProcessInfo processInfo] processName], [formatter stringFromDate:[NSDate date]]];
        [fileContents appendFormat:@"// Source file: %@\n", inputFilePath];
        [fileContents appendString:@"// WARNING: This file was auto-generated. Do not modify by hand.\n\n"];

        [fileContents appendString:@"#import <Foundation/Foundation.h>\n\n"];
        [fileContents appendString:@"#define GENLocalizedString(__key__,__fallback__) [[NSBundle mainBundle] localizedStringForKey:(__key__) value:(__fallback__) table:nil]\n\n"];

        NSUInteger maxLength = 0;
        for(NSString *key in plist) {
            maxLength = MAX(key.length, maxLength);
        }
        
        for (NSString *key in plist) {
            [fileContents appendString:[NSString stringWithFormat:@"#define %@ GENLocalizedString(%@, @%@)\n", padLeft(key, maxLength), padLeft([NSString stringWithFormat:@"@\"%@\"", key], maxLength + 3), repr(plist[key])]];
        }
        if(outputFilePath.length != 0) {
            NSString *parentPath = [outputFilePath stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] fileExistsAtPath:parentPath]) {
                if (![[NSFileManager defaultManager] createDirectoryAtPath:parentPath
                                               withIntermediateDirectories:YES
                                                                attributes:nil
                                                                     error:&error]) {
                    printf("ERROR: Creating parent directory failed with error: %s\n", error.localizedDescription.UTF8String);
                    exit(EXIT_FAILURE);
                }
            }
            
            if (![fileContents writeToFile:outputFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
                printf("ERROR: Writing output file failed with error: %s\n", error.localizedDescription.UTF8String);
                exit(EXIT_FAILURE);
            }
        } else {
            write(STDOUT_FILENO, fileContents.UTF8String, fileContents.length);
        }

        exit(EXIT_SUCCESS);

    }
    return 0;
}