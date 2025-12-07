#import "WawonaAboutPanel.h"

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// iOS: Full implementation
@implementation WawonaAboutPanel

+ (instancetype)sharedAboutPanel {
    static WawonaAboutPanel *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"About Wawona";
        self.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    return self;
}

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create scroll view for content
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    
    // Create content view
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 20;
    contentStack.alignment = UIStackViewAlignmentCenter;
    [scrollView addSubview:contentStack];
    
    // App name
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Wawona";
    titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [contentStack addArrangedSubview:titleLabel];
    
    // Version
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"Version 1.0.0";
    versionLabel.font = [UIFont systemFontOfSize:16];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [contentStack addArrangedSubview:versionLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = @"Wayland Compositor for iOS\nBuilt with Metal rendering\nSupports Waypipe forwarding";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor secondaryLabelColor];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    [contentStack addArrangedSubview:descLabel];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [contentStack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:40],
        [contentStack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:20],
        [contentStack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-20],
        [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-40],
        [contentStack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-40],
    ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self
        action:@selector(dismissAbout:)];
}

- (void)dismissAbout:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAboutPanel:(id)sender {
    // Already a UIViewController, can be presented directly
    (void)sender;
}

@end

#else // macOS implementation
@implementation WawonaAboutPanel

+ (instancetype)sharedAboutPanel {
    static WawonaAboutPanel *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 550)
                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [window setTitle:@"About Wawona"];
    [window center];
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    
    // Remove minimize and fullscreen buttons
    [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupAboutView];
    }
    return self;
}

- (void)setupAboutView {
    NSView *contentView = self.window.contentView;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 20;
    stack.edgeInsets = NSEdgeInsetsMake(40, 40, 40, 40);
    stack.alignment = NSLayoutAttributeCenterX;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:40],
        [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-40],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
    
    // App Name
    NSTextField *title = [[NSTextField alloc] init];
    title.stringValue = @"Wawona";
    title.font = [NSFont systemFontOfSize:36 weight:NSFontWeightBold];
    title.alignment = NSTextAlignmentCenter;
    title.bezeled = NO;
    title.drawsBackground = NO;
    title.editable = NO;
    title.selectable = NO;
    [stack addArrangedSubview:title];
    
    // Subtitle
    NSTextField *subtitle = [[NSTextField alloc] init];
    subtitle.stringValue = @"A native macOS Wayland Compositor";
    subtitle.font = [NSFont systemFontOfSize:16];
    subtitle.alignment = NSTextAlignmentCenter;
    subtitle.bezeled = NO;
    subtitle.drawsBackground = NO;
    subtitle.editable = NO;
    subtitle.selectable = NO;
    [stack addArrangedSubview:subtitle];
    
    // Version (try to read from Info.plist, fallback to defaults)
    NSString *version = @"1.0.0";
    NSString *build = @"0";
    NSString *copyright = @"Copyright © 2025 Alex Spaulding";
    
    // Try to read from bundle Info.plist
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    if (infoDict) {
        if (infoDict[@"CFBundleShortVersionString"]) {
            version = infoDict[@"CFBundleShortVersionString"];
        }
        if (infoDict[@"CFBundleVersion"]) {
            build = infoDict[@"CFBundleVersion"];
        }
        if (infoDict[@"NSHumanReadableCopyright"]) {
            copyright = infoDict[@"NSHumanReadableCopyright"];
        }
    }
    
    // Version string (format: Version MAJOR.MINOR.PATCH (BUILD))
    NSString *versionString = [NSString stringWithFormat:@"Version %@ (%@)", version, build];
    NSTextField *versionField = [[NSTextField alloc] init];
    versionField.stringValue = versionString;
    versionField.font = [NSFont systemFontOfSize:12];
    versionField.textColor = [NSColor secondaryLabelColor];
    versionField.alignment = NSTextAlignmentCenter;
    versionField.bezeled = NO;
    versionField.drawsBackground = NO;
    versionField.editable = NO;
    versionField.selectable = NO;
    [stack addArrangedSubview:versionField];
    
    NSTextField *copyrightField = [[NSTextField alloc] init];
    copyrightField.stringValue = copyright;
    copyrightField.font = [NSFont systemFontOfSize:10];
    copyrightField.textColor = [NSColor secondaryLabelColor];
    copyrightField.alignment = NSTextAlignmentCenter;
    copyrightField.bezeled = NO;
    copyrightField.drawsBackground = NO;
    copyrightField.editable = NO;
    copyrightField.selectable = NO;
    [stack addArrangedSubview:copyrightField];
    
    // View Source Code button (in About Wawona section)
    NSButton *githubButton = [[NSButton alloc] init];
    [githubButton setTitle:@"View Source Code"];
    [githubButton setButtonType:NSButtonTypeMomentaryPushIn];
    [githubButton setBezelStyle:NSBezelStyleRounded];
    [githubButton setTarget:self];
    [githubButton setAction:@selector(openGitHubLink:)];
    [stack addArrangedSubview:githubButton];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    // Credits Section
    NSTextField *creditsTitle = [[NSTextField alloc] init];
    creditsTitle.stringValue = @"Credits";
    creditsTitle.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    creditsTitle.alignment = NSTextAlignmentCenter;
    creditsTitle.bezeled = NO;
    creditsTitle.drawsBackground = NO;
    creditsTitle.editable = NO;
    creditsTitle.selectable = NO;
    [stack addArrangedSubview:creditsTitle];
    
    // Horizontal container for photo and text
    NSView *photoTextContainer = [[NSView alloc] init];
    photoTextContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:photoTextContainer];
    
    // GitHub Profile Photo (left side)
    NSImageView *avatarView = [[NSImageView alloc] init];
    avatarView.imageScaling = NSImageScaleProportionallyUpOrDown;
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.image = [NSImage imageNamed:NSImageNameUser]; // Placeholder
    [photoTextContainer addSubview:avatarView];
    
    // Load GitHub avatar asynchronously
    [self loadGitHubAvatar:avatarView];
    
    // Vertical stack for name, bio, and portfolio link (right side)
    NSStackView *textStack = [[NSStackView alloc] init];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.spacing = 8;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [photoTextContainer addSubview:textStack];
    
    // Name
    NSTextField *aboutMeTitle = [[NSTextField alloc] init];
    aboutMeTitle.stringValue = @"Alex Spaulding";
    aboutMeTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    aboutMeTitle.alignment = NSTextAlignmentLeft;
    aboutMeTitle.bezeled = NO;
    aboutMeTitle.drawsBackground = NO;
    aboutMeTitle.editable = NO;
    aboutMeTitle.selectable = NO;
    [textStack addArrangedSubview:aboutMeTitle];
    
    // Bio text (left-aligned)
    NSTextField *aboutMeText = [[NSTextField alloc] init];
    aboutMeText.stringValue = @"CS student at Eastern Washington University\nPursuing a Math minor\nCertified Front-End Developer";
    aboutMeText.font = [NSFont systemFontOfSize:11];
    aboutMeText.textColor = [NSColor secondaryLabelColor];
    aboutMeText.alignment = NSTextAlignmentLeft;
    aboutMeText.bezeled = NO;
    aboutMeText.drawsBackground = NO;
    aboutMeText.editable = NO;
    aboutMeText.selectable = NO;
    aboutMeText.preferredMaxLayoutWidth = 300;
    [textStack addArrangedSubview:aboutMeText];
    
    // Portfolio link (left-aligned)
    NSButton *portfolioButton = [[NSButton alloc] init];
    [portfolioButton setTitle:@"Portfolio: aspauldingcode.com"];
    [portfolioButton setButtonType:NSButtonTypeMomentaryPushIn];
    [portfolioButton setBezelStyle:NSBezelStyleInline];
    [portfolioButton setTarget:self];
    [portfolioButton setAction:@selector(openPortfolioLink:)];
    [portfolioButton setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [textStack addArrangedSubview:portfolioButton];
    
    // Layout constraints for photo and text container
    [NSLayoutConstraint activateConstraints:@[
        // Photo constraints
        [avatarView.leadingAnchor constraintEqualToAnchor:photoTextContainer.leadingAnchor],
        [avatarView.topAnchor constraintEqualToAnchor:photoTextContainer.topAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:80],
        [avatarView.heightAnchor constraintEqualToConstant:80],
        [avatarView.bottomAnchor constraintLessThanOrEqualToAnchor:photoTextContainer.bottomAnchor],
        
        // Text stack constraints
        [textStack.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor constant:15],
        [textStack.trailingAnchor constraintEqualToAnchor:photoTextContainer.trailingAnchor],
        [textStack.topAnchor constraintEqualToAnchor:photoTextContainer.topAnchor],
        [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:photoTextContainer.bottomAnchor],
        
        // Container height
        [photoTextContainer.heightAnchor constraintGreaterThanOrEqualToConstant:80]
    ]];
    
    // Horizontal stack for buttons
    NSStackView *buttonStack = [[NSStackView alloc] init];
    buttonStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonStack.spacing = 15;
    buttonStack.alignment = NSLayoutAttributeCenterY;
    buttonStack.distribution = NSStackViewDistributionFillEqually;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:buttonStack];
    
    // Donate button
    NSButton *donateButton = [[NSButton alloc] init];
    [donateButton setTitle:@"Donate to Alex Spaulding"];
    [donateButton setButtonType:NSButtonTypeMomentaryPushIn];
    [donateButton setBezelStyle:NSBezelStyleRounded];
    [donateButton setTarget:self];
    [donateButton setAction:@selector(openDonateLink:)];
    [buttonStack addArrangedSubview:donateButton];
}

- (NSBox *)createSeparator {
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.widthAnchor constraintEqualToConstant:400].active = YES;
    [separator.heightAnchor constraintEqualToConstant:1].active = YES;
    return separator;
}

- (void)showAboutPanel:(id)sender {
    [self showWindow:sender];
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openDonateLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://ko-fi.com/aspauldingcode"]];
}

- (void)openGitHubLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/aspauldingcode/Wawona"]];
}

- (void)openPortfolioLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://aspauldingcode.com"]];
}

- (void)loadGitHubAvatar:(NSImageView *)imageView {
    // GitHub API endpoint for user avatar
    // Using a larger size (128x128) for better quality
    NSString *avatarURLString = @"https://github.com/aspauldingcode.png?size=128";
    NSURL *avatarURL = [NSURL URLWithString:avatarURLString];
    
    if (!avatarURL) {
        return;
    }
    
    // Load avatar asynchronously
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:avatarURL
                                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response; // Unused parameter
        if (error || !data) {
            NSLog(@"[ABOUT] Failed to load GitHub avatar: %@", error.localizedDescription);
            return;
        }
        
        NSImage *avatarImage = [[NSImage alloc] initWithData:data];
        if (avatarImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                imageView.image = avatarImage;
                // Make it circular
                imageView.wantsLayer = YES;
                imageView.layer.cornerRadius = 40.0;
                imageView.layer.masksToBounds = YES;
            });
        }
    }];
    
    [task resume];
}

@end
#endif

