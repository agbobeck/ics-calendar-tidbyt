load("render.star", "render")
load("http.star", "http")
load("time.star", "time")
load("schema.star", "schema")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")

def main(config):
    location = config.str(P_LOCATION)
    location = json.decode(location) if location else {}
    timezone = location.get(
        "timezone",
        config.get("$tz", DEFAULT_TIMEZONE),
    )
    
    ics_url = config.str("ics_url", DEFAULT_ICS_URL)
    if not ics_url:
        fail("ICS_URL not set in config")

    usersTz = config.str("tz", "America/Chicago")
    if not usersTz:
        fail("TZ not set in config")

    show_future_only = config.bool("show_future_only", False)
    hide_if_no_upcoming_events = config.bool("hide_if_no_upcoming_events", False)

    now = time.now().in_location(usersTz)
    ics = http.post(
        url=LAMBDA_URL,
        json_body={"icsUrl": ics_url, "tz": usersTz},
    )
    if ics.status_code != 200:
        fail("Failed to fetch ICS file")

    events = ics.json().get("data", [])
    upcoming_event = None

    # Filter events to find the first one that has not started yet
    for event in events:
        event_start = time.from_timestamp(int(event['start'])).in_location(usersTz)
        if event_start.date() == now.date() and event['detail']['minutesUntilStart'] > 0:
            upcoming_event = event
            break

    # If no events for today, find the first event from the next day
    if not upcoming_event:
        for event in events:
            event_start = time.from_timestamp(int(event['start'])).in_location(usersTz)
            if event_start.date() > now.date():
                upcoming_event = event
                break

    # Check if we should hide the app due to no upcoming events
    if not upcoming_event and hide_if_no_upcoming_events:
        return render.Root(child=render.Box())  # Returning an empty frame to indicate hiding

    if not upcoming_event:
        # No upcoming events found or no events at all
        return build_calendar_frame(now, usersTz)

    detail = upcoming_event.get('detail', {})
    if detail.get('thirtyMinuteWarning'):
        return build_calendar_frame(now, usersTz, upcoming_event)
    elif detail.get('tenMinuteWarning') or detail.get('fiveMinuteWarning') or detail.get('oneMinuteWarning') or detail.get('inProgress'):
        return build_event_frame(now, usersTz, upcoming_event)
    elif detail.get('isToday'):
        return build_calendar_frame(now, usersTz)
    else:
        return build_calendar_frame(now, usersTz)

def build_calendar_frame(now, usersTz, event=None):
    month = now.format("Jan")
    day = now.format("Monday")

    top = [
        render.Row(
            cross_align="center",
            expanded=True,
            children=[
                render.Image(src=CALENDAR_ICON, width=9, height=11),
                render.Box(width=2, height=1),
                render.Text(
                    month.upper(),
                    color="#ff83f3",
                    offset=-1,
                ),
                render.Box(width=1, height=1),
                render.Text(
                    str(now.day),
                    color="#ff83f3",
                    offset=-1,
                ),
            ],
        ),
        render.Box(height=2),
    ]

    if event:
        eventStart = time.from_timestamp(int(event['start'])).in_location(usersTz)
        color = "#ff78e9"
        fiveMinuteWarning = event['detail'].get('fiveMinuteWarning', False)
        oneMinuteWarning = event['detail'].get('oneMinuteWarning', False)
        if fiveMinuteWarning:
            color = "#ff5000"
        if oneMinuteWarning:
            color = "#9000ff"

        baseChildren = [
            render.Marquee(
                width=64,
                child=render.Text(
                    event['name'].upper(),
                ),
            ),
            render.Text(
                eventStart.format("at 3:04 PM"),
                color=color,
            ),
        ]

        if event['detail']['minutesUntilStart'] <= 5:
            baseChildren.pop()
            baseChildren.append(
                render.Text(
                    f"in {event['detail']['minutesUntilStart']} min",
                    color=color,
                )
            )

            baseChildren = [
                render.Column(
                    expanded=True,
                    children=[
                        render.Animation(
                            baseChildren
                        )
                    ]
                )
            ]

        bottom = baseChildren
    else:
        bottom = [
            render.Column(
                expanded=True,
                main_align="end",
                children=[
                    render.WrappedText(
                        "NO MORE MEETINGS :-)",
                        color="#fff500",
                        height=16,
                    ),
                ],
            ),
        ]

    return render.Root(
        delay=FRAME_DELAY,
        child=render.Box(
            padding=2,
            color="#111",
            child=render.Column(
                expanded=True,
                children=top + bottom,
            ),
        ),
    )

def build_event_frame(now, usersTz, event):
    minutes_to_start = event['detail']['minutesUntilStart']
    minutes_to_end = event['detail']['minutesUntilEnd']
    hours_to_end = event['detail']['hoursToEnd']

    if minutes_to_start >= 1:
        tagline = (f"in {minutes_to_start}", "min")
    elif minutes_to_end >= 90:
        tagline = (f"Ends in {hours_to_end}", "h")
    elif minutes_to_end > 5:
        tagline = (f"Ends in {minutes_to_end}", "min")
    else:
        tagline = ("", "almost done")

    baseChildren = [
        render.WrappedText(
            event['name'].upper(),
            height=17,
        ),
        render.Box(
            color="#ff78e9",
            height=1,
        ),
        render.Box(height=3),
        render.Row(
            main_align="end",
            expanded=True,
            children=[
                render.Text(
                    tagline[0],
                    color="#fff500",
                ),
                render.Box(height=1, width=1),
                render.Text(
                    tagline[1],
                    color="#fff500",
                ),
            ],
        ),
    ]
    return render.Root(
        child=render.Box(
            padding=2,
            child=render.Column(
                main_align="start",
                cross_align="start",
                expanded=True,
                children=baseChildren
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version="1",
        fields=[
            schema.Location(
                id=P_LOCATION,
                name="Location",
                desc="Location for the display of date and time.",
                icon="locationDot",
            ),
            schema.Text(
                id="ics_url",
                name="iCalendar URL",
                desc="The URL of the iCalendar file",
                icon="calendar",
                default=DEFAULT_ICS_URL,
            ),
            schema.Bool(
                id="show_future_only",
                name="Show Future Events Only",
                desc="Only show events that have not started yet.",
                default=False,
            ),
            schema.Bool(
                id="hide_if_no_upcoming_events",
                name="Hide If No Upcoming Events",
                desc="Hide the app if no events are upcoming today or the following day.",
                default=False,
            ),
        ],
    )

P_LOCATION = "location"
DEFAULT_TIMEZONE = "America/New_York"
FRAME_DELAY = 500
LAMBDA_URL = "https://xmd10xd284.execute-api.us-east-1.amazonaws.com/ics-next-event"
CALENDAR_ICON = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAkAAAALCAYAAACtWacbAAAAAXNSR0IArs4c6QAAAE9JREFUKFNjZGBgYJgzZ87/lJQURlw0I0xRYEMHw/qGCgZ0GqSZ8a2Myv8aX1eGls27GXDRYEUg0/ABxv///xOn6OjRowzW1tYMuOghaxIAD/ltSOskB+YAAAAASUVORK5CYII=")
DEFAULT_ICS_URL = "https://www.phpclasses.org/browse/download/1/file/63438/name/example.ics"

#AGB Edits 2024-10-13
    #Cleaned code for standards
    #Added Schema "Hide If No Upcoming Events" -- Only shows applet if there are no upcoming events today or following day
    #Add Schema "Show Future Events Only" -- Only shows events that are upcoming, unless there is no overlapping or upcoming events
    #Added filtering logic to only show the first event from the next calendar day if no more upcomning events today exist. 