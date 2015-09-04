//
//  ViewController.m
//  Augenklinik
//
//  Created by Daniel Böhringer on 23.08.15.
//  Copyright © 2015 Daniel Böhringer. All rights reserved.
//
// TODO:
//   <!> nachsorgetermin eintragen

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@import EventKit;

@interface ViewController ()

// The database with calendar events and reminders
@property (strong, nonatomic) EKEventStore *eventStore;

// Indicates whether app has access to event store.
@property (nonatomic) BOOL isAccessToEventStoreGranted;

@property (strong, nonatomic) EKCalendar *calendar;

@property (copy, nonatomic) NSArray *reminders;

@property (weak, nonatomic) IBOutlet UIDatePicker *wakeupTimePicker;
@property (weak, nonatomic) IBOutlet UIDatePicker *sleepTimePicker;
@property (weak, nonatomic) IBOutlet UIView *scanView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (strong, nonatomic)  UIView *highlightView;
@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDevice *device;
@property (strong, nonatomic) AVCaptureDeviceInput *input;
@property (strong, nonatomic) AVCaptureMetadataOutput *output;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *captureLayer;


@end

#define CALENDAR_NAME @"Augenklinik"

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self updateAuthorizationStatusToAccessEventStore];
	
	_highlightView = [[UIView alloc] init];
	_highlightView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
	_highlightView.layer.borderColor = [UIColor greenColor].CGColor;
	_highlightView.layer.borderWidth = 3;
	[self.scanView addSubview:_highlightView];

	_session = [[AVCaptureSession alloc] init];
	_device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	NSError *error = nil;
	
	_input = [AVCaptureDeviceInput deviceInputWithDevice:_device error:&error];
	if (_input) {
		[_session addInput:_input];
	} else {
		NSLog(@"Error: %@", error);
	}
	
	_output = [[AVCaptureMetadataOutput alloc] init];
	[_output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
	[_session addOutput:_output];
	
	_output.metadataObjectTypes = [_output availableMetadataObjectTypes];
	
	_captureLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
	_captureLayer.frame = self.view.bounds;
	_captureLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[self.scanView.layer addSublayer:_captureLayer];
	
	[_session startRunning];
	
	[self.scanView bringSubviewToFront:_highlightView];

}

- (EKEventStore *)eventStore {
	if (!_eventStore) {
		_eventStore = [[EKEventStore alloc] init];
	}
	return _eventStore;
}

- (EKCalendar *)calendar {
	if (!_calendar) {
		
		NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeReminder];
		
		NSString *calendarTitle = CALENDAR_NAME;
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title matches %@", calendarTitle];
		NSArray *filtered = [calendars filteredArrayUsingPredicate:predicate];
		
		if ([filtered count]) {
			_calendar = [filtered firstObject];
		} else {
			
			_calendar = [EKCalendar calendarForEntityType:EKEntityTypeReminder eventStore:self.eventStore];
			_calendar.title = CALENDAR_NAME;
			_calendar.source = self.eventStore.defaultCalendarForNewReminders.source;
			
			NSError *calendarErr = nil;
			BOOL calendarSuccess = [self.eventStore saveCalendar:_calendar commit:YES error:&calendarErr];
			if (!calendarSuccess) {
				// Handle error
			}
		}
	}
	return _calendar;
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}
-(unsigned)_secondsBetweenDate:(NSDate *)startHour andDate:(NSDate *)endHour withFrequency:(unsigned)topffrequenz
{
	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *startComponents = [gregorianCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:startHour];
	NSDateComponents *endComponents = [gregorianCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:endHour];
	NSDateComponents *todayComponents = [gregorianCalendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
	todayComponents.hour = startComponents.hour;
	todayComponents.minute = startComponents.minute;
	todayComponents.second = startComponents.second;
	NSDate *startDate = [gregorianCalendar dateFromComponents:todayComponents];
	todayComponents.hour = endComponents.hour;
	todayComponents.minute = endComponents.minute;
	todayComponents.second = endComponents.second;
	NSDate *endDate = [gregorianCalendar dateFromComponents:todayComponents];

	if (topffrequenz < 2) return 0;
	int secondsTotal = (int)([endDate timeIntervalSinceDate:startDate]);
	return (unsigned)(secondsTotal/(topffrequenz - 1));
}

-(BOOL)_addRemindersAtFrequency:(unsigned) topffrequenz secondsBetween:(unsigned)secondsBetween startingHours:(NSDate *)startHour identifier:(NSString *) myIdentifier
{
	BOOL success = YES;
	for (int i=0; i < topffrequenz; i++) {
		NSDate *date = [startHour dateByAddingTimeInterval:secondsBetween * i];
		if (![self addReminderForToDoItem:myIdentifier dueDate:date]) {
			success = FALSE;
			break;
		}
	}
	return success;
}

#define SECONDS_PER_DAY (60*60*24)

-(BOOL)_addRemindersAtFrequency:(unsigned) topffrequenz secondsBetween:(unsigned)secondsBetween startDay:(NSDate *)startDay endDay:(NSDate *)endDay identifier:(NSString *) myIdentifier
{
	unsigned daysBetween= (unsigned)([endDay timeIntervalSinceDate:startDay]/SECONDS_PER_DAY);
	BOOL success = YES;
	for (int i = 0; i < daysBetween; i++) {
		NSDate *date = [startDay dateByAddingTimeInterval: SECONDS_PER_DAY * i];
		if (![self _addRemindersAtFrequency:topffrequenz secondsBetween:secondsBetween startingHours:date identifier:myIdentifier]) {
			success = FALSE;
			break;
		}
	}
	return success;
}

//FIXME: make this run in the background
-(BOOL)addRemindersForSchemaName:(NSString *)schemaName eyePrefix:(NSString *)eyePrefix startHour:(NSDate *)startDate endHours:(NSDate *) endHour
{
	NSDictionary *dn=@{ @"KAT0": @[@{@"id": @"Inflanefran forte AT", @"taper": @[			   @{@"fq":@5, @"d":@7 },
																							   @{@"fq":@4, @"d":@7 },
																							   @{@"fq":@3, @"d":@7 },
																							   @{@"fq":@2, @"d":@7 },
																							   @{@"fq":@1, @"d":@7 }
																							 ]}
											   ]
					  };

	NSArray *schemaArr = [dn objectForKey:schemaName];
	// fixme: raise if schemaArr does not exists
	
	for (NSDictionary *medSeq in schemaArr) {
		NSString *myIdentifier = [medSeq objectForKey:@"id"];
		NSArray  *taperArray = [medSeq objectForKey:@"taper"];
		for (NSDictionary *taperStep in taperArray) {
			unsigned topffrequenz = (unsigned)[[taperStep objectForKey:@"fq"] integerValue],
					 days = (unsigned)[[taperStep objectForKey:@"d"] integerValue];
			NSDate *endDate = [startDate dateByAddingTimeInterval:SECONDS_PER_DAY * days];
			int secondsBetween = [self _secondsBetweenDate:startDate andDate:endHour withFrequency:topffrequenz];
			if (![self _addRemindersAtFrequency:topffrequenz secondsBetween:secondsBetween startDay:startDate endDay:endDate identifier:
				  [NSString stringWithFormat:@"%@: %@",eyePrefix, myIdentifier]]) {
				return FALSE;
			}
			startDate = endDate;
		}
	}
	return YES;
}
-(void)parseScannedString:(NSString *)aString
{
	NSDate *startHour = [_wakeupTimePicker date],
			*endHour  = [_sleepTimePicker date];
	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *startComponents = [gregorianCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:startHour];
	NSDateComponents *todayComponents = [gregorianCalendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
	todayComponents.hour = startComponents.hour;
	todayComponents.minute = startComponents.minute;
	todayComponents.second = startComponents.second;
	NSDate *startDate = [gregorianCalendar dateFromComponents:todayComponents];

	NSCharacterSet  *eyeSet  = [NSCharacterSet characterSetWithCharactersInString:@"RLA"],
					*alnumSet = [NSCharacterSet alphanumericCharacterSet],
				    *dateSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789-"];
	NSScanner *theScanner = [NSScanner scannerWithString:aString];
	theScanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@","];

	[_spinner startAnimating];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString  *eyeString, *medString, *terminString;

		while ([theScanner isAtEnd] == NO) {
			
			[theScanner scanCharactersFromSet:eyeSet
								   intoString:&eyeString];
			[theScanner scanCharactersFromSet:alnumSet
								   intoString:&medString];
			[theScanner scanCharactersFromSet:dateSet
								   intoString:&terminString];
			// FIXME: raise unless eyeString
			[self addRemindersForSchemaName:medString eyePrefix:eyeString startHour:startDate endHours:endHour];
		}
		
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			
			[_spinner stopAnimating];
			NSString *message = @"Alle Erinnerungen eingetragen!";
			UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil
																message:message
															   delegate:self
													  cancelButtonTitle:nil
													  otherButtonTitles:@"Fertig", nil];
			[alertView show];
		});
	});
	return;
}
-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	exit(0);
}
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
	AVMetadataMachineReadableCodeObject *barCodeObject;
	NSString *detectionString = nil;
	NSArray *barCodeTypes = @[AVMetadataObjectTypeUPCECode, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode39Mod43Code,
							  AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeCode128Code,
							  AVMetadataObjectTypePDF417Code, AVMetadataObjectTypeQRCode, AVMetadataObjectTypeAztecCode];
	
	for (AVMetadataObject *metadata in metadataObjects) {
		for (NSString *type in barCodeTypes) {
			if ([metadata.type isEqualToString:type])
			{
				barCodeObject = (AVMetadataMachineReadableCodeObject *)[_captureLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)metadata];
				_highlightView.frame = barCodeObject.bounds;
				detectionString = [(AVMetadataMachineReadableCodeObject *)metadata stringValue];
				break;
			}
		}
		
		if (detectionString != nil)
		{
			NSLog(@"detectionString: %@", detectionString);
			[_session stopRunning];

			[self performSelectorOnMainThread:@selector(parseScannedString:) withObject:detectionString waitUntilDone:NO];
			break;
		}
	}
}


- (void)updateAuthorizationStatusToAccessEventStore {
	EKAuthorizationStatus authorizationStatus = [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
	
	switch (authorizationStatus) {
			// 3
		case EKAuthorizationStatusDenied:
		case EKAuthorizationStatusRestricted: {
			self.isAccessToEventStoreGranted = NO;
			UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Access Denied"
																message:@"This app doesn't have access to your Reminders." delegate:nil
													  cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
			[alertView show];
			break;
		}
			
			// 4
		case EKAuthorizationStatusAuthorized:
			self.isAccessToEventStoreGranted = YES;
			break;
			
			// 5
		case EKAuthorizationStatusNotDetermined: {
			[self.eventStore requestAccessToEntityType:EKEntityTypeReminder
											completion:^(BOOL granted, NSError *error) {
												dispatch_async(dispatch_get_main_queue(), ^{
													self.isAccessToEventStoreGranted = granted;
												});
											}];
			break;
		}
	}
}

- (NSDateComponents *)_dateComponentsForDate:(NSDate *) aDate seconds:(unsigned) secs{
	NSDateComponents *oneDayComponents = [[NSDateComponents alloc] init];
	oneDayComponents.day = 1;
	
	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *components = [gregorianCalendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
														fromDate:aDate];
	components.second = secs;

	return components;
}

- (BOOL)addReminderForToDoItem:(NSString *)item dueDate:(NSDate *) aDate{
	if (!self.isAccessToEventStoreGranted)
		return NO;
	
	if ([aDate compare:[NSDate date]] == NSOrderedAscending) { // do not add overdue events in the first place
		return YES;
	}
	EKReminder *reminder = [EKReminder reminderWithEventStore:self.eventStore];
	reminder.title = item;
	reminder.calendar = self.calendar;
	reminder.startDateComponents = [self _dateComponentsForDate:aDate seconds:0];
	reminder.dueDateComponents = [self _dateComponentsForDate:aDate seconds:50];
	[reminder addAlarm:[EKAlarm alarmWithAbsoluteDate:aDate]];
	
	NSError *error = nil;
	BOOL success = [self.eventStore saveReminder:reminder commit:YES error:&error];
	if (!success) {
		return NO;
	}
	return YES;
}

#if 0
- (void)fetchReminders {
	if (self.isAccessToEventStoreGranted) {

		NSPredicate *predicate =
		[self.eventStore predicateForRemindersInCalendars:@[self.calendar]];
		
		[self.eventStore fetchRemindersMatchingPredicate:predicate completion:^(NSArray *reminders) {
			self.reminders = reminders;
		}];
	}
}

- (void)deleteReminderForToDoItem:(NSString *)item {
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title matches %@", item];
	NSArray *results = [self.reminders filteredArrayUsingPredicate:predicate];
	
	if ([results count]) {
		[results enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			NSError *error = nil;
			BOOL success = [self.eventStore removeReminder:obj commit:NO error:&error];
			if (!success) {
				// Handle delete error
			}
		}];
		
		NSError *commitErr = nil;
		BOOL success = [self.eventStore commit:&commitErr];
		if (!success) {
			// Handle commit error.
		}
	}
}
#endif

@end
