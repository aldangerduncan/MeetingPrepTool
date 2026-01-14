function doGet(e) {
    const action = e.parameter.action || 'calendar';

    if (action === 'email') {
        return getEmail();
    } else if (action === 'schedule') {
        return scheduleReminder(e.parameter);
    } else if (action === 'trigger') {
        // This could be called manually or by a time trigger
        return triggerReminders();
    } else {
        return getCalendar();
    }
}

function doPost(e) {
    try {
        const data = JSON.parse(e.postData.contents);

        // Handle direct email sending from Daily Huddle
        if (data.html) {
            const htmlBody = data.html;
            const subject = data.subject || "Daily Huddle Report";
            const recipient = "alex.sheath@irdgroup.com.au";
            GmailApp.sendEmail(recipient, subject, "Please view the HTML content.", { htmlBody: htmlBody });
            return ContentService.createTextOutput("Email Sent");
        }

        // Handle reminder scheduling via POST
        if (data.action === 'schedule') {
            return scheduleReminder(data);
        }

        return ContentService.createTextOutput("Action not recognized");
    } catch (err) {
        return ContentService.createTextOutput("Error: " + err.toString());
    }
}

function getEmail() {
    const query = 'from:no-reply@prospector.com.au subject:"Your alert has arrived!"';
    const threads = GmailApp.search(query, 0, 1);
    let result = { found: false, body: "" };
    if (threads.length > 0) {
        const messages = threads[0].getMessages();
        const msg = messages[messages.length - 1];
        result.found = true;
        result.subject = msg.getSubject();
        result.date = msg.getDate().toString();
        result.body = msg.getBody();
    }
    return ContentService.createTextOutput(JSON.stringify(result)).setMimeType(ContentService.MimeType.JSON);
}

function getCalendar() {
    const calendarId = 'alex.sheath@irdgroup.com.au';
    const today = new Date();
    const start = new Date(today);
    // If today is Monday (1), look back to Friday (3 days ago). Otherwise yesterday (1 day ago).
    const daysBack = (today.getDay() === 1) ? 3 : 1;
    start.setDate(today.getDate() - daysBack);
    start.setHours(0, 0, 0, 0);
    const end = new Date(today);
    end.setHours(23, 59, 59, 999);

    const calendar = CalendarApp.getCalendarById(calendarId);
    if (!calendar) return ContentService.createTextOutput(JSON.stringify({ error: "Calendar not found" })).setMimeType(ContentService.MimeType.JSON);

    // 1. Get Events Occurring (Agenda)
    const events = calendar.getEvents(start, end);
    const skipTitles = ['Home', 'Daily Huddle', 'IRD Fornightly Payroll', 'Office', 'FRIYAY', 'NB -sheathy', 'Revenue meeting', 'BUSY', 'Edd and Alex 1 on 1'].map(t => t.toLowerCase().trim());

    const outputEvents = events.map(evt => {
        const title = evt.getTitle();
        const cleanTitle = (title || "").toLowerCase().trim();
        if (skipTitles.some(skip => cleanTitle.includes(skip))) return null;

        return {
            title: title,
            start: evt.getStartTime().toString(),
            shortDate: Utilities.formatDate(evt.getStartTime(), Session.getScriptTimeZone(), "d MMM yyyy HH:mm"),
            timeOnly: Utilities.formatDate(evt.getStartTime(), Session.getScriptTimeZone(), "HH:mm"),
            attendees: evt.getGuestList().map(g => g.getEmail()),
            colorId: evt.getColor() || "default",
            googleMeetUrl: getMeetLink_(evt, calendarId),
            location: evt.getLocation() || "",
            description: evt.getDescription() || ""
        };
    }).filter(e => e !== null);

    // 2. Get Events Created (KPI: Meetings Booked)
    const stats = getCreatedEventsStats_(calendarId, start, end, skipTitles);

    return ContentService.createTextOutput(JSON.stringify({
        events: outputEvents,
        count: outputEvents.length,
        stats: stats
    })).setMimeType(ContentService.MimeType.JSON);
}

function getCreatedEventsStats_(calendarId, start, end, skipTitles) {
    // Uses Advanced Calendar Service to find events created in the window (meetings booked)
    // updatedMin catches events touched; we assume created >= start.

    let createdCount = 0;
    let createdList = [];

    try {
        const startStr = start.toISOString();

        let optionalArgs = {
            updatedMin: startStr,
            showDeleted: false,
            singleEvents: true,
            orderBy: 'startTime',
            maxResults: 100
        };

        const response = Calendar.Events.list(calendarId, optionalArgs);
        const items = response.items || [];

        items.forEach(ev => {
            if (!ev.created) return;
            const createdTime = new Date(ev.created);

            if (createdTime >= start && createdTime <= end) {
                const title = ev.summary || "(No Title)";
                const cleanTitle = title.toLowerCase().trim();

                if (skipTitles.some(skip => cleanTitle.includes(skip))) return;

                createdCount++;

                let startTimeStr = "";
                if (ev.start.dateTime) {
                    startTimeStr = Utilities.formatDate(new Date(ev.start.dateTime), Session.getScriptTimeZone(), "d MMM HH:mm");
                } else if (ev.start.date) {
                    startTimeStr = ev.start.date + " (All Day)";
                }

                createdList.push({
                    title: title,
                    startTime: startTimeStr,
                    createdTime: Utilities.formatDate(createdTime, Session.getScriptTimeZone(), "HH:mm")
                });
            }
        });

    } catch (e) {
        Logger.log("Error fetching created stats: " + e.message);
        return { createdCount: 0, createdList: [], error: e.message };
    }

    return { createdCount: createdCount, createdList: createdList };
}

function getMeetLink_(evt, calendarId) {
    // 1. Check Location & Description (Fallback for pasted links)
    const meetRegex = /https:\/\/meet\.google\.com\/[a-z\-]+/i;
    const loc = evt.getLocation() || "";
    const desc = evt.getDescription() || "";

    let match = loc.match(meetRegex);
    if (!match) match = desc.match(meetRegex);
    if (match) return match[0];

    // 2. Try Advanced Calendar Service (For native Meet links)
    // REQUIRES: "Calendar API" service enabled in Apps Script
    try {
        const eventId = evt.getId().split('@')[0];
        const fullEvent = Calendar.Events.get(calendarId, eventId);
        if (fullEvent.hangoutLink) return fullEvent.hangoutLink;
        if (fullEvent.conferenceData && fullEvent.conferenceData.entryPoints) {
            const videoEntry = fullEvent.conferenceData.entryPoints.find(ep => ep.entryPointType === 'video');
            if (videoEntry) return videoEntry.uri;
        }
    } catch (e) {
        // Fallback or log if Calendar API is not enabled
        Logger.log("Advanced Calendar Service not enabled or error: " + e.message);
    }

    return "";
}

/**
 * Reminders Logic
 */

function scheduleReminder(params) {
    const ss = SpreadsheetApp.getActiveSpreadsheet() || SpreadsheetApp.create("Meeting Reminders");
    let sheet = ss.getSheetByName("SheetOne");
    if (!sheet) {
        sheet = ss.insertSheet("SheetOne");
        sheet.appendRow(["Recipient", "First", "TimeScheduled", "GoogleMeetURL", "Email Sent", "Status", "Title"]);
    }

    const data = sheet.getDataRange().getValues();
    // Check if this meeting (recipient + time) is already scheduled and NOT yet sent
    const alreadyExists = data.some(row =>
        row[0] === params.email &&
        row[2] == params.time && // Uses == for loose comparison if types differ
        row[4] === ''
    );

    if (alreadyExists) {
        return ContentService.createTextOutput("Reminder already exists for " + params.email);
    }

    // params: email, name, time, meetUrl, title
    sheet.appendRow([
        params.email,
        params.name.split(' ')[0],
        params.time,
        params.meetUrl,
        '',
        'Scheduled',
        params.title // New Title column for live verification
    ]);

    // Ensure a minute-by-minute trigger is set up
    setupTrigger_();

    return ContentService.createTextOutput("Reminder Scheduled for " + params.email);
}

function setupTrigger_() {
    const triggers = ScriptApp.getProjectTriggers();
    if (triggers.some(t => t.getHandlerFunction() === 'triggerReminders')) return;
    ScriptApp.newTrigger('triggerReminders').timeBased().everyMinutes(1).create();
}

/**
 * Core Mail Merge Logic (Based on user script)
 */
function triggerReminders() {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) return;
    const sheet = ss.getSheetByName("SheetOne");
    if (!sheet) return;

    const subjectLine = "Today's catch up with Alex from Prospector";
    let emailTemplate;
    try {
        emailTemplate = getGmailTemplateFromDrafts_(subjectLine);
    } catch (e) {
        Logger.log(e.message);
        return ContentService.createTextOutput(e.message);
    }

    const dataRange = sheet.getDataRange();
    const data = dataRange.getDisplayValues();
    const heads = data.shift();

    const RECIPIENT_COL = heads.indexOf("Recipient");
    const FIRST_COL = heads.indexOf("First");
    const TIME_COL = heads.indexOf("TimeScheduled");
    const MEET_COL = heads.indexOf("GoogleMeetURL");
    const SENT_COL = heads.indexOf("Email Sent");

    const now = new Date();
    const out = [];

    data.forEach(function (row, rowIdx) {
        let outputVal = row[SENT_COL];

        if (row[SENT_COL] === '' && row[RECIPIENT_COL] !== '') {
            const scheduledTimeStr = row[TIME_COL];
            const meetUrl = row[MEET_COL];

            // Only send if Google Meet URL exists
            if (scheduledTimeStr && meetUrl && meetUrl !== "") {
                const [hours, minutes] = scheduledTimeStr.split(':').map(Number);
                const scheduledTime = new Date();
                scheduledTime.setHours(hours, minutes, 0, 0);

                const diffMinutes = (scheduledTime.getTime() - now.getTime()) / 60000;

                // Send if within 6 minutes of meeting (to catch the 5 min window)
                if (diffMinutes <= 6 && diffMinutes >= 0) {
                    // LIVE CHECK: Verify meeting still exists on Calendar
                    const calendar = CalendarApp.getCalendarById('alex.sheath@irdgroup.com.au');
                    const liveEvents = calendar.getEvents(scheduledTime, new Date(scheduledTime.getTime() + 60000));
                    const stillExists = liveEvents.some(e => e.getTitle() === row[heads.indexOf("Title")] || e.getGuestList().some(g => g.getEmail() === row[RECIPIENT_COL]));

                    if (!stillExists) {
                        outputVal = "Cancelled/Moved";
                    } else {
                        try {
                            const rowObj = {};
                            heads.forEach((h, i) => rowObj[h] = row[i]);

                            const msgObj = fillInTemplateFromObject_(emailTemplate.message, rowObj);
                            GmailApp.sendEmail(row[RECIPIENT_COL], msgObj.subject, msgObj.text, {
                                htmlBody: msgObj.html,
                                attachments: emailTemplate.attachments,
                                inlineImages: emailTemplate.inlineImages
                            });
                            outputVal = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd HH:mm");
                        } catch (e) {
                            outputVal = "Error: " + e.message;
                        }
                    }
                }
            }
        }
        out.push([outputVal]);
    });

    if (out.length > 0) {
        sheet.getRange(2, SENT_COL + 1, out.length, 1).setValues(out);
    }
    return ContentService.createTextOutput("Reminders Processed");
}

function getGmailTemplateFromDrafts_(subject_line) {
    const drafts = GmailApp.getDrafts();
    const draft = drafts.filter(d => d.getMessage().getSubject() === subject_line)[0];
    if (!draft) throw new Error("Oops - can't find Gmail draft with subject: " + subject_line);

    const msg = draft.getMessage();
    const allInlineImages = msg.getAttachments({ includeInlineImages: true, includeAttachments: false });
    const attachments = msg.getAttachments({ includeInlineImages: false });
    const htmlBody = msg.getBody();

    const img_obj = allInlineImages.reduce((obj, i) => (obj[i.getName()] = i, obj), {});
    const imgexp = RegExp('<img.*?src="cid:(.*?)".*?alt="(.*?)"[^\>]+>', 'g');
    const matches = [...htmlBody.matchAll(imgexp)];
    const inlineImagesObj = {};
    matches.forEach(match => inlineImagesObj[match[1]] = img_obj[match[2]]);

    return {
        message: { subject: subject_line, text: msg.getPlainBody(), html: htmlBody },
        attachments: attachments,
        inlineImages: inlineImagesObj
    };
}

function fillInTemplateFromObject_(template, data) {
    let template_string = JSON.stringify(template);
    template_string = template_string.replace(/{{[^{}]+}}/g, key => {
        const field = key.replace(/[{}]+/g, "");
        return escapeData_(data[field] || "");
    });
    return JSON.parse(template_string);
}

function escapeData_(str) {
    return str.toString()
        .replace(/[\\]/g, '\\\\')
        .replace(/[\"]/g, '\\"')
        .replace(/[\/]/g, '\\/')
        .replace(/[\b]/g, '\\b')
        .replace(/[\f]/g, '\\f')
        .replace(/[\n]/g, '\\n')
        .replace(/[\r]/g, '\\r')
        .replace(/[\t]/g, '\\t');
}

