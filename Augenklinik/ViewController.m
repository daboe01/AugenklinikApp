//
//  ViewController.m
//  Augenklinik
//
//  Created by Daniel Böhringer on 23.08.15.
//  Copyright © 2015 Daniel Böhringer. All rights reserved.
//

#import "ViewController.h"

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
@property (weak, nonatomic) IBOutlet UISlider *tropfSlider;
@property (weak, nonatomic) IBOutlet UITextField *tropfField;

@end

#define CALENDAR_NAME @"Augenklinik"

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	[self updateAuthorizationStatusToAccessEventStore];
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


-(IBAction)didPressButton:(id)sender
{
	NSDate *startHour = [_wakeupTimePicker date],
			*endHour  = [_sleepTimePicker date];
	int secondsTotal = (int)([endHour timeIntervalSinceDate:startHour]);
	int topffrequenz = [_tropfField.text intValue];
	int secondsBetween = (int)(secondsTotal/(topffrequenz - 1));
	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *startComponents = [gregorianCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:startHour];
	NSDateComponents *todayComponents = [gregorianCalendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
	todayComponents.hour = startComponents.hour;
	todayComponents.minute = startComponents.minute;
	todayComponents.second = startComponents.second;
	NSDate *startDate = [gregorianCalendar dateFromComponents:todayComponents];


	BOOL success = [self _addRemindersAtFrequency:topffrequenz secondsBetween:secondsBetween startingHours:startDate identifier:@"RA: Inflanefran forte"];
	NSString *message = (success) ? @"All reminders have been added!" : @"Failed to add reminders!";
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
	[alertView show];
}

-(IBAction)didChangeSlider:(UISlider*)sender
{
	int val=(int)[sender value];
	_tropfField.text=[NSString stringWithFormat:@"%d", val];
	
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


@end
