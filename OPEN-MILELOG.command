#!/bin/zsh
# Open the iPhone app project, not the test package.
MILELOG_PROJECT_DIR="${0:A:h}"
/usr/bin/open -a Xcode "$MILELOG_PROJECT_DIR/MileLog.xcodeproj"
