#!/bin/sh
set -ex

PRODUCT_NAME="GitUp"
APPCAST_NAME="appcast.xml"
XCODE_SYMROOT="/tmp/$PRODUCT_NAME"

MAX_VERSION=`git tag -l "b*" | sed 's/b//g' | sort -nr | head -n 1`
VERSION=$((MAX_VERSION + 1))

##### Count LOC

$CLOC_PATH --by-file --xml --out=cloc.xml "GitUp/Application" "GitUpKit/Components" "GitUpKit/Core" "GitUpKit/Extensions" "GitUpKit/Interface" "GitUpKit/Utilities" "GitUpKit/Views"

##### Run unit tests

# pushd "GitUpKit"
# rm -rf "$XCODE_SYMROOT"
# xcodebuild test -scheme "GitUpKit (OSX)" "SYMROOT=$XCODE_SYMROOT"
# popd

##### Archive and export app

pushd "GitUp"
xcodebuild archive -scheme "Application" -archivePath "../build/$PRODUCT_NAME.xcarchive" "BUNDLE_VERSION=$VERSION" # SYMROOT is ignored?
xcodebuild -exportArchive -archivePath "../build/$PRODUCT_NAME.xcarchive" -exportPath "../build/$PRODUCT_NAME"  # SYMROOT is ignored?
ditto -c -k --keepParent "../build/$PRODUCT_NAME.xcarchive" "../build/$PRODUCT_NAME.xcarchive.zip"
popd "GitUp"

##### Tag build

git tag -f "b$VERSION"
git push -f origin "b$VERSION"

##### Upload to S3 and update Appcast

FULL_PRODUCT_NAME="$PRODUCT_NAME.app"
PRODUCT_PATH="$WORKSPACE/build/$PRODUCT_NAME.xcarchive/Products/Applications/$FULL_PRODUCT_NAME"
INFO_PLIST_PATH="$PRODUCT_PATH/Contents/Info.plist"
VERSION_ID=`defaults read "$INFO_PLIST_PATH" "CFBundleVersion"`  # Must be full path
VERSION_STRING=`defaults read "$INFO_PLIST_PATH" "CFBundleShortVersionString"`
MIN_OS=`defaults read "$INFO_PLIST_PATH" "LSMinimumSystemVersion"`

ARCHIVE_NAME="$PRODUCT_NAME.zip"
BACKUP_ARCHIVE_NAME="$PRODUCT_NAME-$VERSION_ID.zip"
APPCAST_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$APPCAST_NAME"
ARCHIVE_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$ARCHIVE_NAME"
BACKUP_ARCHIVE_URL="https://s3-us-west-2.amazonaws.com/gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME"

ARCHIVE_PATH="$TMPDIR/$ARCHIVE_NAME"
APPCAST_PATH="$WORKSPACE/GitUp/SparkleAppcast.xml"

/usr/bin/ditto -c -k --keepParent "$PRODUCT_PATH" "$ARCHIVE_PATH"

ARCHIVE_SIZE=`stat -f "%z" "$ARCHIVE_PATH"`

EDITED_APPCAST_PATH="$TMPDIR/appcast.xml"
/usr/bin/perl -p -e "s|__APPCAST_TITLE__|$PRODUCT_NAME|g;s|__APPCAST_URL__|$APPCAST_URL|g;s|__VERSION_ID__|$VERSION_ID|g;s|__VERSION_STRING__|$VERSION_STRING|g;s|__ARCHIVE_URL__|$ARCHIVE_URL|g;s|__ARCHIVE_SIZE__|$ARCHIVE_SIZE|g;s|__MIN_OS__|$MIN_OS|g" "$APPCAST_PATH" > "$EDITED_APPCAST_PATH"

/usr/local/bin/aws s3 cp "$ARCHIVE_PATH" "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME"
/usr/local/bin/aws s3 cp "s3://gitup-builds/$CHANNEL/$BACKUP_ARCHIVE_NAME" "s3://gitup-builds/$CHANNEL/$ARCHIVE_NAME"
/usr/local/bin/aws s3 cp "$EDITED_APPCAST_PATH" "s3://gitup-builds/$CHANNEL/$APPCAST_NAME"
