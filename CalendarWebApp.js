function doGet(e) {
    e = e || {};
    const action = (e.parameter || {}).action || 'calendar';

    if (action === 'email') {
        return getEmail();
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
            googleMeetUrl: getMeetingUrl_(evt, calendarId),
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

/**
 * Returns the best meeting URL from an event: Google Meet, Teams, or empty string.
 */
function getMeetingUrl_(evt, calendarId) {
    const loc = evt.getLocation() || "";
    const desc = evt.getDescription() || "";
    const combined = loc + " " + desc;

    // Google Meet
    const meetMatch = combined.match(/https:\/\/meet\.google\.com\/[a-z\-]+/i);
    if (meetMatch) return meetMatch[0];

    // Microsoft Teams
    const teamsMatch = combined.match(/https:\/\/teams\.microsoft\.com\/l\/meetup-join\/[^\s"<>]+/i);
    if (teamsMatch) return teamsMatch[0];

    // Fallback: Calendar API hangoutLink
    try {
        const eventId = evt.getId().split('@')[0];
        const fullEvent = Calendar.Events.get(calendarId, eventId);
        if (fullEvent.hangoutLink) return fullEvent.hangoutLink;
        if (fullEvent.conferenceData && fullEvent.conferenceData.entryPoints) {
            const videoEntry = fullEvent.conferenceData.entryPoints.find(ep => ep.entryPointType === 'video');
            if (videoEntry) return videoEntry.uri;
        }
    } catch (e) {
        Logger.log("Calendar API error in getMeetingUrl_: " + e.message);
    }

    return ""; // Face-to-face or phone — no link
}

/**
 * Automatic Reminder System
 * -------------------------
 * Run setupAutoReminders() once from the Apps Script editor to activate.
 * After that, checkCalendarForReminders() fires every minute on Google's servers
 * — no action required on your laptop.
 */

function setupAutoReminders() {
    // Remove any existing reminder triggers to avoid duplicates
    ScriptApp.getProjectTriggers()
        .filter(t => ['triggerReminders', 'checkCalendarForReminders'].includes(t.getHandlerFunction()))
        .forEach(t => ScriptApp.deleteTrigger(t));
    ScriptApp.newTrigger('checkCalendarForReminders').timeBased().everyMinutes(1).create();
    Logger.log('Auto reminder trigger created. Reminders will fire 5 minutes before meetings where you are the organiser.');
}

function checkCalendarForReminders() {
    const calendarId = 'alex.sheath@irdgroup.com.au';
    const now = new Date();

    // Window: 3–7 minutes from now — reliably catches the 5-minute mark within a 1-min polling cycle
    const windowStart = new Date(now.getTime() + 3 * 60000);
    const windowEnd   = new Date(now.getTime() + 7 * 60000);

    const calendar = CalendarApp.getCalendarById(calendarId);
    if (!calendar) return;

    const events = calendar.getEvents(windowStart, windowEnd);
    if (events.length === 0) return;

    let emailTemplate;
    try {
        emailTemplate = getGmailTemplateFromDrafts_("Today's catch up with Alex from Prospector");
    } catch (e) {
        Logger.log('Reminder template not found: ' + e.message);
        return;
    }

    events.forEach(evt => {
        try {
            // Only send if Alex is the organiser
            const eventId = evt.getId().split('@')[0];
            const fullEvent = Calendar.Events.get(calendarId, eventId);
            const organiserEmail = (fullEvent.organizer || {}).email || '';
            if (organiserEmail.toLowerCase() !== calendarId.toLowerCase()) return;

            const meetUrl = getMeetingUrl_(evt, calendarId);
            const startTime = Utilities.formatDate(evt.getStartTime(), Session.getScriptTimeZone(), "HH:mm");

            evt.getGuestList().forEach(guest => {
                const recipientEmail = guest.getEmail();
                if (!recipientEmail || recipientEmail.toLowerCase() === calendarId.toLowerCase()) return;

                if (isAlreadySent_(recipientEmail, evt.getStartTime())) return;

                const guestName = guest.getName() || '';
                const firstName = guestName ? guestName.split(' ')[0] : recipientEmail.split('@')[0];

                const rowData = {
                    Recipient: recipientEmail,
                    First: firstName,
                    TimeScheduled: startTime,
                    GoogleMeetURL: meetUrl,
                    Title: evt.getTitle()
                };

                const msgObj = fillInTemplateFromObject_(emailTemplate.message, rowData);
                GmailApp.sendEmail(recipientEmail, msgObj.subject, msgObj.text, {
                    htmlBody: msgObj.html,
                    attachments: emailTemplate.attachments,
                    inlineImages: emailTemplate.inlineImages
                });

                logSent_(recipientEmail, firstName, evt.getStartTime(), meetUrl, evt.getTitle());
                Logger.log('Reminder sent to ' + recipientEmail + ' for: ' + evt.getTitle() + ' at ' + startTime);
            });
        } catch (e) {
            Logger.log('Error processing event "' + evt.getTitle() + '": ' + e.message);
        }
    });
}

/**
 * Returns the log sheet, creating the spreadsheet on first run and persisting
 * its ID via PropertiesService (required since getActiveSpreadsheet() is null
 * when called from a time-based trigger).
 */
function getOrCreateLogSheet_() {
    const props = PropertiesService.getScriptProperties();
    let ssId = props.getProperty('REMINDER_SS_ID');
    let ss;
    if (ssId) {
        try { ss = SpreadsheetApp.openById(ssId); } catch(e) { ssId = null; }
    }
    if (!ss) {
        ss = SpreadsheetApp.create('Meeting Reminders');
        props.setProperty('REMINDER_SS_ID', ss.getId());
    }
    let sheet = ss.getSheetByName('Log');
    if (!sheet) {
        sheet = ss.insertSheet('Log');
        sheet.appendRow(["Recipient", "First", "MeetingTime", "MeetingTitle", "GoogleMeetURL", "SentAt"]);
    }
    return sheet;
}

function isAlreadySent_(email, meetingStart) {
    const sheet = getOrCreateLogSheet_();
    const data = sheet.getDataRange().getValues();
    const startStr = meetingStart.toISOString().substring(0, 16); // "YYYY-MM-DDTHH:MM"
    return data.some(row =>
        row[0] === email &&
        String(row[2] instanceof Date ? row[2].toISOString() : row[2]).substring(0, 16) === startStr &&
        row[5] !== ''
    );
}

function logSent_(email, firstName, meetingStart, meetUrl, title) {
    const sheet = getOrCreateLogSheet_();
    sheet.appendRow([
        email,
        firstName,
        meetingStart,
        title,
        meetUrl,
        Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd HH:mm")
    ]);
}

/**
 * Mail merge helpers (unchanged)
 */

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
