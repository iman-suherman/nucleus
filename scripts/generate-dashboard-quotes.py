#!/usr/bin/env python3
"""Generate DashboardQuotes.json — day-of-week and time-of-day inspirational quotes."""

from __future__ import annotations

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATHS = [
    ROOT / "app/Nucleus/Resources/DashboardQuotes.json",
    ROOT / "nucleus-apple/Packages/NucleusCore/Sources/NucleusCore/Resources/DashboardQuotes.json",
]
QUOTES_PER_SET = 1000
MIN_LENGTH = 80
MAX_LENGTH = 220

PERIODS = ("morning", "afternoon", "evening", "night")
WORK_DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday")
LEISURE_DAYS = ("saturday", "sunday", "holiday")

WEEKDAY_TEMPLATES = {
    "morning": [
        "Start strong and protect the first quiet hour — your clearest thinking is waiting for you before the day grows loud.",
        "A focused morning turns small steps into real momentum; choose one meaningful priority and let everything else follow.",
        "Wake your ambition gently and meet the day with steady intent — progress loves a calm, confident beginning.",
        "Your best work often begins before the inbox opens; give your attention to what matters most while your mind is fresh.",
        "Channel fresh energy into the task that will move the needle, then carry that sense of purpose into everything else.",
        "Begin with purpose and the rest of the day will align — you do not need perfection, only a honest start.",
        "Turn intention into action one deliberate move at a time; momentum is built in minutes, not in grand gestures alone.",
        "Let clarity lead your first decisions today, and trust that a single well-chosen step can reshape the whole day.",
        "Build momentum early and guard it carefully — the habits you set before noon often echo until evening.",
        "A bright start makes every challenge feel smaller; meet the morning as someone who is ready, not rushed.",
        "Trust your preparation and step forward — this is the hour when focus is a gift worth using wisely.",
        "Make the first hour yours and the day will follow; protect it from noise, hurry, and unnecessary distraction.",
        "Start where you are, with what you have — progress rarely waits for ideal conditions, but it rewards steady intent.",
        "Set the tone with one meaningful win before lunch, and let that quiet satisfaction carry you through the hours ahead.",
        "Rise with purpose and let discipline do the rest; you already have more capacity than the morning noise suggests.",
        "Today opens with possibility — meet it with patience, courage, and a plan simple enough to actually begin.",
        "Let the morning sharpen your priorities instead of scattering them; one clear goal is enough to start well.",
        "You do not need to do everything today — you need to begin the right thing with enough care that it counts.",
        "Treat this hour as an investment, not a race; the calm you bring now will return to you all day long.",
        "Step into the day knowing that steady effort, not frantic speed, is what builds lasting results.",
    ],
    "afternoon": [
        "The middle of the day is where steady workers shine — keep moving, breathe deeply, and choose the next right task.",
        "When the pace picks up, protect your attention; busy hours are proof you are making things happen, not proof you must hurry.",
        "Momentum matters more than perfect timing now — finish one meaningful piece of work and let that completion reset your focus.",
        "Stay centered amid the noise; your edge is not speed alone, but the ability to prioritize when everything feels urgent.",
        "Push through the rush with patience — completion is closer than it feels, and small wins still count as real progress.",
        "One task at a time cuts through afternoon clutter better than any elaborate plan made under pressure.",
        "Your consistency in busy moments builds results that last longer than bursts of frantic effort ever could.",
        "Do not let urgency scatter you — hold your line, keep your standards high, and finish what you started this morning.",
        "The grind is temporary, but the progress is permanent; stay practical and trust the work you have already done.",
        "Midday energy may fade, yet discipline can carry you forward when motivation alone would quietly walk away.",
        "Refocus for one honest hour and the whole day can shift — clarity often returns the moment you simplify your aim.",
        "You are doing more than you think; keep going with the kind of steady pace that respects both effort and sanity.",
        "Busy is not the same as productive — choose wisely, close one loop at a time, and leave room to breathe.",
        "Let the afternoon reward patience: finish what matters, release what does not, and move with intention rather than noise.",
        "When everything demands your attention, give it selectively — your best work still deserves your best focus.",
        "Stand in the middle of the day with confidence; this is where persistence turns plans into something real.",
        "Take a breath, reset your posture, and return to the task — progress often resumes the moment you stop fighting the clock.",
        "Hold steady through the rush; the people who finish strong are rarely the ones who sprint without direction.",
        "Use these hours to convert intention into done — even one completed task can restore order to a chaotic day.",
        "Keep your standards high, but your pace humane; excellence and exhaustion are not the same achievement.",
    ],
    "evening": [
        "Wrap up with intention and close the loops that matter — a thoughtful finish turns a busy day into a satisfying one.",
        "Review what you accomplished, release what remains, and leave work at work with enough pride to rest well.",
        "The day is winding down; tie up what matters most and let completion be your final act before you sign off.",
        "Evening clarity comes when you stop starting and start finishing — honor your effort with a clean, honest ending.",
        "Close your open tabs, mental and digital, and step back knowing you gave the day your genuine attention.",
        "Finish strong because tomorrow will thank you for the order you leave behind, not the chaos you carry home.",
        "Set up the next day by closing today's loose ends — future you deserves a morning that begins without yesterday's weight.",
        "Done is better than perfect when the light is fading; finish what you can and plan the rest without guilt.",
        "Let completion replace hurry — cross one more meaningful item off, then give yourself permission to stop.",
        "A thoughtful wrap-up transforms noise into progress; end the workday with a sense of done, not just stopped.",
        "Step back, review, and release the day with pride — you do not need to earn rest by exhausting yourself first.",
        "Leave your desk knowing you gave honest effort; that is enough to close the chapter and move into the evening.",
        "Evening focus is about closure, not new beginnings — protect this hour for finishing, reflecting, and letting go.",
        "Your effort today deserves a proper ending; close what you started and trust that rest is part of the work too.",
        "Finish what you can with care, then stop cleanly — boundaries at night protect the energy you need tomorrow.",
        "Review the day without harsh judgment; notice what moved forward and let the rest wait until it truly must.",
        "Close the chapter with intention — the calm that follows completion is one of the day's quiet rewards.",
        "Tie up loose ends before the evening claims you; order at the end of the day becomes peace at the start of the next.",
        "Let the final hour be about completion and gratitude, not about squeezing in one more unnecessary task.",
        "Sign off with clarity — when you know what is done and what can wait, rest arrives more easily.",
    ],
    "night": [
        "Rest well tonight — recovery is not a pause from excellence, it is the foundation tomorrow's performance is built on.",
        "Release the day and trust that nothing truly urgent survives until morning; your mind deserves quiet as much as your body needs sleep.",
        "Recharge tonight so you can show up fully tomorrow — let go of unfinished lists and allow sleep to do its honest work.",
        "Wind down with intention; your energy is worth protecting, and night is for restoring, not replaying the day in your head.",
        "Give yourself permission to stop thinking about work — deep rest is how great days begin, not an reward you must earn twice.",
        "Unplug, unwind, and let silence refill what the day drained away; tomorrow can wait for the person you are becoming tonight.",
        "Your best ideas often arrive after a good night's sleep, so close the laptop and trust the quiet hours ahead.",
        "Rest is not lazy — it is how you sustain excellence over weeks and months instead of burning bright for a single day.",
        "Close your eyes knowing you earned this pause; sleep is the final task of a well-lived workday done with care.",
        "Let peaceful darkness wrap around your thoughts and loosen the grip of every unfinished conversation still echoing inside.",
        "Release tension on purpose — your body is asking for recovery, and answering that request is an act of wisdom, not weakness.",
        "Tomorrow's energy starts with tonight's rest; drift off without carrying today's weight into the hours meant for healing.",
        "Recharge completely — you deserve uninterrupted peace, a soft landing, and a mind free enough to dream again.",
        "Night is for restoring what effort consumes; protect it from guilt, noise, and the habit of always doing one more thing.",
        "Let go of the day in layers — first the urgency, then the noise, then the need to solve everything before sunrise.",
        "Sleep is part of the work when the work is sustained over time; treat rest as seriously as any meeting on your calendar.",
        "Quiet hours rebuild the focus you will need again — honor them by choosing stillness over one last scroll through obligation.",
        "You have done enough for today; let the night hold you without asking for anything back except your willingness to rest.",
        "Recovery tonight makes courage easier tomorrow — trust the process of stopping, breathing, and beginning again in the morning.",
        "Drift off gently, without bargaining with the clock — the day is complete, and so for now are you.",
    ],
}

LEISURE_TEMPLATES = {
    "morning": [
        "Slow mornings are a luxury — savor every unhurried minute and let sunlight set the pace instead of the calendar.",
        "No alarm for ambition today; wake up curious about what delights the day might bring and follow them without apology.",
        "A lazy start is sometimes the most restorative thing you can do — restful beginnings make the whole day feel lighter.",
        "Let comfort lead this morning; productivity can wait until Monday while you remember what it feels like to breathe deeply.",
        "Weekend mornings are for coffee, not calendars — start the day without a to-do list and leave room for spontaneous joy.",
        "Give yourself permission to move at human speed; today belongs to you, not your obligations or anyone else's urgency.",
        "Ease into the day like it is a gift unwrapped slowly — there is nowhere you need to be yet, and that is the point.",
        "Morning without rush is medicine for the soul; trade urgency for presence and notice how much softer the world becomes.",
        "Your only deadline today is happiness — wake refreshed and let the hours unfold naturally, without forcing a plan.",
        "Unscheduled hours are where memories are made; protect this morning from the habit of filling every quiet space.",
        "Let sunlight and silence be your only agenda for a while — the best leisure often begins with nothing at all.",
        "Start the day open-handed, not open-laptop — leisure is not laziness, it is the space where life outside work grows.",
        "Breathe deeply and listen to the day waking up around you; slowness is not wasted time when your spirit needs it.",
        "Weekend light hits differently — soak it in, stay unhurried, and let the morning stretch as wide as you need.",
        "Choose ease before efficiency today; a gentle start makes room for laughter, curiosity, and unexpected delight.",
        "Today is yours to inhabit, not to optimize — let joy set the pace and trust that rest can be enough.",
        "Move through the morning without measuring it; some of the best days begin with no plan beyond feeling alive.",
        "Let the first hour be soft, warm, and uncommitted — you have earned the right to begin without performing productivity.",
        "Wake into a day with fewer demands and more permission; leisure mornings restore the parts of you work cannot reach.",
        "Stay in the moment a little longer than usual — the world will still be there when you decide to meet it.",
    ],
    "afternoon": [
        "Afternoon adventures beat afternoon meetings every time — explore, wander, or simply do nothing, and call each choice valid.",
        "Free time is not wasted time; it is living time, and the best afternoons often have no agenda beyond feeling present.",
        "Let curiosity guide you somewhere unexpected — weekend hours are for experiences, not obligations waiting in your inbox.",
        "Play, rest, or connect; your choice is the right one when it fills you up instead of draining what the week took.",
        "Do what restores you, not what impresses anyone else — leisure is allowed to be simple, quiet, and entirely yours.",
        "Somewhere beautiful may be closer than you think; step outside and let the afternoon remind you there is life beyond tasks.",
        "Lose track of time on purpose today — joy does not need a schedule to show up when you stop watching the clock.",
        "Afternoon freedom is worth protecting fiercely; be where your feet are, not where work would prefer you to be.",
        "Let laughter be the loudest thing this afternoon — holiday hours are precious, so spend them on what actually matters.",
        "Choose pleasure over productivity without guilt; the world looks different when you are not always in a hurry.",
        "Make space for something that makes you smile, even if it serves no purpose beyond making the day feel fuller.",
        "Unplug for a while and remember what you are working for — a life with room in it for ease, people, and wonder.",
        "Live a little today; you have earned these unclaimed hours, and they are not less important because they are unscheduled.",
        "The best afternoons leave you feeling fed in ways a finished task list never could — follow what nourishes you.",
        "Wander without a destination if you want to — not every hour needs a reason to justify its existence.",
        "Give the afternoon to friendship, sunlight, movement, or stillness; all are worthy uses of a day that belongs to you.",
        "Let the middle of the day be wide and unhurried — leisure is the art of letting enough be enough.",
        "Step away from the rhythm of the workweek and listen to what you actually feel like doing right now.",
        "Celebrate the freedom of a day without deadlines; even small pleasures become brighter when nothing is chasing you.",
        "Be present where you are and let the afternoon stretch — recovery can look like adventure, rest, or both.",
    ],
    "evening": [
        "Evening is for people, not projects — share a meal, a story, or a quiet moment with someone who makes life feel warmer.",
        "Let the sunset remind you that endings can be beautiful; slow down and notice how good a day off truly feels.",
        "Wrap the day in warmth: good food, good company, and the kind of rest that reaches deeper than simply stopping work.",
        "No emails tonight — only conversations that matter, laughter that lands easily, and moments too small to photograph but too good to miss.",
        "Celebrate the freedom of a day without deadlines and let gratitude for simple pleasures fill the evening air.",
        "Tonight is for recharging your heart, not your inbox; put away screens and pick up moments instead.",
        "Watch the sky change and let your mind wander — holiday evenings deserve extra kindness toward yourself.",
        "Weekend evenings are for connection, not completion; be fully here while tomorrow's work waits politely outside the door.",
        "Share your time generously — it is one of the few gifts that grows richer the more you give it away.",
        "Reflect on joy, not tasks, as the day closes; the best evenings end with contentment, not exhaustion.",
        "Let music, laughter, or silence be your soundtrack tonight — evening calm is the reward for choosing rest over rush.",
        "End the day feeling fed in every sense of the word: nourished, seen, rested, and quietly glad to be alive.",
        "Give the evening to people, places, or peace — all three can repair what a demanding week slowly wears down.",
        "Let the night begin with softness; you do not need to maximize a day off for it to have been worthwhile.",
        "Notice how much lighter life feels when nothing urgent is waiting in the next hour — stay inside that feeling awhile.",
        "Turn toward what comforts you tonight — leisure evenings are for restoring the heart as much as the body.",
        "Close the day with warmth instead of measurement; happiness rarely needs proof to be real.",
        "Be here for the small rituals that make a house feel like home — they matter more than productivity ever will on days like this.",
        "Let conversation, food, or quiet companionship anchor the evening; connection is its own kind of restoration.",
        "Release the week gently and step into the night knowing you are allowed to simply enjoy what remains of the day.",
    ],
    "night": [
        "Sleep in tomorrow if you can — you have earned every extra minute, and leisure nights are meant to be unhurried.",
        "Let the night hold you without asking for anything back; drift off knowing nothing needs you until morning.",
        "Weekend nights are for deep rest and sweet dreams — release the week because you have carried enough for now.",
        "Night is nature's way of saying you have done enough; rest without guilt, because recovery is part of living well.",
        "Close your eyes to a world without deadlines and let peaceful darkness wrap around every thought still trying to perform.",
        "Tomorrow can wait; tonight is for restoration, softness, and the quiet pleasure of having nowhere else to be.",
        "Holiday nights are for sleeping without an alarm — trust your body to take the rest it has been waiting for all week.",
        "Your body knows how to heal when you stop interrupting it; let sleep work overnight while you finally let go.",
        "Quiet nights rebuild what busy weeks deplete — dream freely, because Monday is still far enough away to stop counting.",
        "Sink into comfort and leave the world outside; leisure days deserve leisure nights without apology or second thoughts.",
        "Nighttime peace is one of the weekend's final gifts — receive it fully instead of spending the dark hours planning ahead.",
        "Rest deeply tonight; play hard if you did, sleep harder now, and remember that stopping is also a skill worth practicing.",
        "Let go of everything except the pillow beneath you and the simple truth that you are allowed to be off duty.",
        "Sweet dreams are earned by days well spent away from obligation — close the chapter gently and trust the morning to wait.",
        "Recharge fully; the best kind of night asks nothing from you except your willingness to disappear into rest for a while.",
        "Release the habit of reviewing the day for improvement and let the night be complete in its own quiet way.",
        "Drift toward sleep without bargaining — the weekend is still here, and so is the permission to do nothing more today.",
        "Protect these hours from guilt and glow of screens; darkness is not empty, it is where tired minds become whole again.",
        "Let the night restore what effort cannot — peace, perspective, and the soft reset only deep sleep can truly provide.",
        "Fall asleep knowing leisure was not wasted time; it was the work of becoming human again after a week of demands.",
    ],
}


DAY_QUALIFIERS: dict[str, dict[str, list[str]]] = {
    "monday": {
        "morning": ["On Monday morning,", "At the start of the week,", "This Monday,", "As the week begins,"],
        "afternoon": ["On Monday afternoon,", "Midday Monday,", "This Monday afternoon,", "Through Monday's middle hours,"],
        "evening": ["On Monday evening,", "As Monday closes,", "This Monday nightfall,", "Before Tuesday arrives,"],
        "night": ["On Monday night,", "As Monday ends,", "This Monday evening,", "Before Tuesday begins,"],
    },
    "tuesday": {
        "morning": ["On Tuesday morning,", "This Tuesday,", "At Tuesday's fresh start,", "With Tuesday ahead of you,"],
        "afternoon": ["On Tuesday afternoon,", "Midweek Tuesday,", "This Tuesday afternoon,", "Through Tuesday's busy hours,"],
        "evening": ["On Tuesday evening,", "As Tuesday winds down,", "This Tuesday nightfall,", "Before Wednesday arrives,"],
        "night": ["On Tuesday night,", "As Tuesday ends,", "This Tuesday evening,", "Before Wednesday begins,"],
    },
    "wednesday": {
        "morning": ["On Wednesday morning,", "At midweek,", "This Wednesday,", "Halfway through the week,"],
        "afternoon": ["On Wednesday afternoon,", "Midweek Wednesday,", "This Wednesday afternoon,", "At the week's midpoint,"],
        "evening": ["On Wednesday evening,", "As Wednesday closes,", "This Wednesday nightfall,", "Before Thursday arrives,"],
        "night": ["On Wednesday night,", "As Wednesday ends,", "This Wednesday evening,", "Before Thursday begins,"],
    },
    "thursday": {
        "morning": ["On Thursday morning,", "This Thursday,", "With the week maturing,", "As Thursday opens,"],
        "afternoon": ["On Thursday afternoon,", "This Thursday afternoon,", "Through Thursday's steady hours,", "Late in the workweek,"],
        "evening": ["On Thursday evening,", "As Thursday winds down,", "This Thursday nightfall,", "Before Friday arrives,"],
        "night": ["On Thursday night,", "As Thursday ends,", "This Thursday evening,", "Before Friday begins,"],
    },
    "friday": {
        "morning": ["On Friday morning,", "This Friday,", "At the week's final stretch,", "As Friday begins,"],
        "afternoon": ["On Friday afternoon,", "This Friday afternoon,", "Through Friday's closing hours,", "As the workweek nears its end,"],
        "evening": ["On Friday evening,", "As Friday closes,", "This Friday nightfall,", "As the week completes,"],
        "night": ["On Friday night,", "As Friday ends,", "This Friday evening,", "Before the weekend fully arrives,"],
    },
    "saturday": {
        "morning": ["On Saturday morning,", "This Saturday,", "At the weekend's open door,", "On a slow Saturday,"],
        "afternoon": ["On Saturday afternoon,", "This Saturday afternoon,", "Through an unhurried Saturday,", "Midweekend Saturday,"],
        "evening": ["On Saturday evening,", "As Saturday softens,", "This Saturday nightfall,", "Before Sunday arrives,"],
        "night": ["On Saturday night,", "As Saturday ends,", "This Saturday evening,", "Before Sunday begins,"],
    },
    "sunday": {
        "morning": ["On Sunday morning,", "This Sunday,", "At the week's gentle pause,", "On a restful Sunday,"],
        "afternoon": ["On Sunday afternoon,", "This Sunday afternoon,", "Through a peaceful Sunday,", "Before the week returns,"],
        "evening": ["On Sunday evening,", "As Sunday closes,", "This Sunday nightfall,", "Before Monday arrives,"],
        "night": ["On Sunday night,", "As Sunday ends,", "This Sunday evening,", "Before a new week begins,"],
    },
    "holiday": {
        "morning": ["On this holiday morning,", "This public holiday,", "On a day away from routine,", "During this holiday,"],
        "afternoon": ["On this holiday afternoon,", "This holiday afternoon,", "Through a well-earned holiday,", "On a day of rest,"],
        "evening": ["On this holiday evening,", "As the holiday softens,", "This holiday nightfall,", "On a day worth savoring,"],
        "night": ["On this holiday night,", "As the holiday ends,", "This holiday evening,", "Before routine returns,"],
    },
}

OPENERS = ["Remember:", "Note to self:", "Today:", "Right now:", "Quietly:", "Gently:", "Honestly:"]
CLOSERS = [
    " Keep going with care.",
    " Make this hour count.",
    " You have what it takes.",
    " Enjoy the moment fully.",
    " Trust the pace you choose.",
    " Let that be enough for now.",
]
TAILS = [
    " Carry that thought with you.",
    " Let it guide the next step.",
    " Hold onto that feeling.",
    " That is enough for now.",
    " Let it settle in quietly.",
]

WORK_PHRASES = {
    "morning": {
        "openings": [
            "Start the day with one clear priority",
            "Give your first hour to meaningful work",
            "Protect the morning from noise and hurry",
            "Meet the day with steady, honest intent",
            "Let fresh energy shape your first decisions",
            "Build momentum before the inbox takes over",
            "Choose focus over frenzy this morning",
            "Turn intention into one deliberate first step",
            "Treat early hours as an investment in clarity",
            "Begin where you are and move with purpose",
            "Make room for deep work while your mind is sharp",
            "Set a calm tone the rest of the day can follow",
            "Lead with discipline before distraction arrives",
            "Trust preparation and take the first step bravely",
            "Let simplicity guide your opening choices",
        ],
        "middles": [
            "because progress loves a patient beginning",
            "and let everything else wait its turn",
            "so the rest of the day can align around it",
            "before urgency starts speaking louder than wisdom",
            "while your attention is still yours to give",
            "and carry that sense of purpose forward",
            "instead of trying to solve the whole week at once",
            "knowing small wins compound faster than grand plans",
            "without needing perfect conditions to begin",
            "then protect that momentum like something fragile and valuable",
            "and notice how much lighter the day feels when you do",
            "trusting that one honest step can reshape the hours ahead",
            "even when the task list looks longer than your energy",
            "because excellence is built in minutes, not in speeches",
            "and let completion become your first reward",
        ],
        "closings": [
            "You have enough capacity for a strong start.",
            "Make this hour count before the world grows loud.",
            "Keep going with care and confidence.",
            "Let that be enough to begin well.",
            "Trust the pace you choose this morning.",
        ],
    },
    "afternoon": {
        "openings": [
            "In the middle of the day",
            "When the pace picks up",
            "Stay centered amid the noise",
            "Hold your line through busy hours",
            "Refocus for one honest stretch",
            "Keep moving with practical patience",
            "Let consistency outlast urgency",
            "Finish one meaningful piece of work",
            "Choose the next right task deliberately",
            "Push through the rush without losing standards",
            "Use these hours to convert intent into done",
            "Stand in the afternoon with quiet confidence",
            "Do not confuse busy with productive",
            "Protect attention when everything feels urgent",
            "Let discipline carry you when motivation fades",
        ],
        "middles": [
            "and remember that steady effort still counts",
            "because completion is closer than it feels",
            "one task at a time, without apology",
            "even when the calendar keeps multiplying demands",
            "trusting that small wins restore order quickly",
            "and release what cannot be finished today",
            "without letting pressure scatter your priorities",
            "knowing persistence turns plans into something real",
            "then breathe before choosing what comes next",
            "and keep your standards humane as well as high",
            "because the grind is temporary but progress lasts",
            "while you close loops that actually matter",
            "instead of chasing every ping and interruption",
            "and let one finished task reset your focus",
            "so the day ends feeling earned, not merely survived",
        ],
        "closings": [
            "You are doing more than you think.",
            "Keep going with care.",
            "Make this hour count.",
            "Trust the work you have already done.",
            "Let that be enough for now.",
        ],
    },
    "evening": {
        "openings": [
            "As the day winds down",
            "Before you sign off",
            "Use the evening for thoughtful closure",
            "Wrap up with intention",
            "Review what moved forward today",
            "Close the loops that matter most",
            "Let completion replace hurry",
            "Finish strong because tomorrow will notice",
            "Step back with honest pride in your effort",
            "Tie up loose ends before rest arrives",
            "Give the day a clean ending",
            "Leave work at work with enough order behind you",
            "Set up tomorrow by closing today well",
            "Honor your effort with a proper finish",
            "Choose closure over one more unnecessary task",
        ],
        "middles": [
            "and release what can wait until morning",
            "knowing done is better than perfect tonight",
            "without replaying every unfinished conversation",
            "so future you begins without yesterday's weight",
            "then stop cleanly when enough is truly enough",
            "and let gratitude replace measurement for a moment",
            "because boundaries at night protect tomorrow's energy",
            "while you notice what actually got done",
            "instead of measuring the day only by what remains",
            "trusting that rest is part of sustained excellence",
            "and let the final hour be about finishing, not starting",
            "even if the list is not empty yet",
            "because a thoughtful wrap-up turns noise into progress",
            "then give yourself permission to be off duty",
            "and carry calm into the hours meant for recovery",
        ],
        "closings": [
            "You have done enough for today.",
            "Rest will meet you more easily now.",
            "Let that be enough to close the chapter.",
            "Tomorrow can begin fresher because of this.",
            "Sign off with clarity and kindness.",
        ],
    },
    "night": {
        "openings": [
            "Before sleep takes over",
            "Tonight, release the day",
            "Let the night rebuild what effort consumed",
            "Rest is not a pause from excellence",
            "Give your mind permission to stop performing",
            "Unplug from obligation and trust the quiet",
            "Recovery tonight makes courage easier tomorrow",
            "Protect these hours from guilt and noise",
            "Sleep is part of the work when the work is long",
            "Wind down with intention instead of one last scroll",
            "Close your eyes knowing you earned this pause",
            "Let peaceful darkness loosen the day's grip",
            "Tomorrow's best ideas often need tonight's rest",
            "Drift off without bargaining with the clock",
            "You have carried enough for one day",
        ],
        "middles": [
            "and let nothing truly urgent survive until morning",
            "because deep rest is how great days begin",
            "without carrying unfinished lists into bed",
            "trusting your body to heal when you stop interrupting it",
            "so your energy returns before the alarm returns",
            "and allow silence to refill what the day drained away",
            "knowing stopping is also a skill worth practicing",
            "then leave the world outside for a while",
            "because night is for restoring, not reviewing",
            "and let go in layers: urgency first, then noise",
            "even when habit whispers that one more thing matters",
            "while sleep does its honest work overnight",
            "instead of replaying every decision in the dark",
            "and remember that you are allowed to be off duty",
            "so tomorrow meets you softer than today ended",
        ],
        "closings": [
            "Rest well tonight.",
            "Sweet dreams are earned, not postponed.",
            "Let the night hold you gently.",
            "Tomorrow can wait for now.",
            "That is enough for today.",
        ],
    },
}

LEISURE_PHRASES = {
    "morning": {
        "openings": [
            "Slow mornings are a gift",
            "Let comfort lead today",
            "Wake without rushing the hour",
            "Ease into the day at human speed",
            "Trade urgency for presence this morning",
            "Start open-handed, not open-laptop",
            "Give yourself permission to move slowly",
            "Let sunlight set the pace instead of the calendar",
            "Choose ease before efficiency today",
            "Stay in the moment a little longer than usual",
            "Begin without a to-do list breathing down your neck",
            "Make room for curiosity before obligation",
            "Protect this morning from unnecessary plans",
            "Let the first hour be soft and uncommitted",
            "Weekend light deserves an unhurried start",
        ],
        "middles": [
            "and savor every minute that belongs only to you",
            "because leisure is not laziness, it is restoration",
            "without measuring the hour against productivity",
            "while the world waits patiently outside the door",
            "knowing restful beginnings make the whole day lighter",
            "then follow delight wherever it quietly appears",
            "and notice how much softer life feels unscheduled",
            "even when habit says you should be doing more",
            "because some of the best days begin with nothing planned",
            "trusting that slowness can be medicine for the soul",
            "and let joy set the pace without apology",
            "instead of filling every quiet space from reflex",
            "so your spirit gets room to breathe again",
            "then move through the morning without performing busyness",
            "and remember there is nowhere you need to be yet",
        ],
        "closings": [
            "Enjoy the moment fully.",
            "Let that be enough for now.",
            "Today belongs to you.",
            "Make this hour count in the gentlest way.",
            "Rest can be enough.",
        ],
    },
    "afternoon": {
        "openings": [
            "This afternoon is for living, not optimizing",
            "Free time is not wasted time",
            "Let curiosity guide you somewhere unexpected",
            "Choose pleasure over productivity without guilt",
            "Step outside and remember there is life beyond tasks",
            "Make space for what actually fills you up",
            "Lose track of time on purpose today",
            "Protect these unclaimed hours fiercely",
            "Do what restores you, not what impresses anyone",
            "Celebrate the freedom of a day without deadlines",
            "Wander without a destination if you want to",
            "Give the afternoon to friendship, sunlight, or stillness",
            "Unplug for a while and remember why you work",
            "Live a little today without needing justification",
            "Let the middle of the day be wide and unhurried",
        ],
        "middles": [
            "and follow what nourishes you in the moment",
            "because joy does not need a schedule to show up",
            "without apologizing for choosing ease",
            "knowing recovery can look like adventure, rest, or both",
            "then laugh loudly enough to drown out the workweek",
            "and be where your feet are, not where email prefers you",
            "even if the choice is simply to do nothing at all",
            "because holiday hours are precious and worth guarding",
            "while you let the afternoon stretch without a clock",
            "and notice how bright small pleasures become unhurried",
            "instead of turning leisure into another performance",
            "so the day feels fed in ways a task list never could",
            "trusting that presence is its own kind of achievement",
            "then share your time with someone who warms the room",
            "and call every honest choice valid",
        ],
        "closings": [
            "You have earned these hours.",
            "Enjoy the moment fully.",
            "Let that be enough for now.",
            "Make this afternoon count on your terms.",
            "Rest and delight are both worthwhile.",
        ],
    },
    "evening": {
        "openings": [
            "Evening is for people, not projects",
            "Let the sunset remind you endings can be beautiful",
            "Wrap the day in warmth and good company",
            "No emails tonight, only moments that matter",
            "Share a meal, a story, or quiet companionship",
            "Turn toward what comforts you tonight",
            "Reflect on joy instead of tasks as the day closes",
            "Give the evening to connection and calm",
            "Watch the sky change and let your mind wander",
            "Close the day feeling fed in every sense",
            "Let music, laughter, or silence be your soundtrack",
            "Release the week gently and stay fully here",
            "Notice how much lighter life feels off the clock",
            "End the day with warmth instead of measurement",
            "Celebrate simple pleasures before the night arrives",
        ],
        "middles": [
            "and put away screens in favor of presence",
            "because leisure evenings restore the heart as well as the body",
            "without needing to maximize a day off to justify it",
            "knowing happiness rarely needs proof to be real",
            "then let conversation anchor you somewhere kind",
            "and be grateful for hours that belong to you alone",
            "even when tomorrow's routine waits just beyond the door",
            "because the best evenings end in contentment, not exhaustion",
            "while you share time generously with people who matter",
            "and let the night begin with softness, not obligation",
            "instead of reviewing the day for improvement one last time",
            "so rest arrives as a reward, not a negotiation",
            "trusting that connection is its own restoration",
            "then step into the night knowing you enjoyed what remained",
            "and leave the workweek outside for a while longer",
        ],
        "closings": [
            "Enjoy the moment fully.",
            "Let that be enough for tonight.",
            "Rest will meet you kindly.",
            "Tomorrow's work can wait outside the door.",
            "You deserve this ease.",
        ],
    },
    "night": {
        "openings": [
            "Sleep in tomorrow if you can",
            "Let the night hold you without asking for anything back",
            "Weekend nights are for deep rest and sweet dreams",
            "Holiday nights deserve sleep without an alarm",
            "Close your eyes to a world without deadlines",
            "Rest deeply because you have done enough for now",
            "Protect these hours from guilt and glow of screens",
            "Sink into comfort and leave the world outside",
            "Nighttime peace is one of the weekend's final gifts",
            "Release the habit of planning ahead in the dark",
            "Drift toward sleep without bargaining",
            "Let go of everything except the pillow beneath you",
            "Recovery tonight makes tomorrow gentler before it begins",
            "Fall asleep knowing leisure was not wasted time",
            "Quiet nights rebuild what busy weeks deplete",
        ],
        "middles": [
            "and trust your body to take the rest it has been waiting for",
            "because Monday is still far enough away to stop counting",
            "without reviewing the day for one more improvement",
            "knowing darkness is where tired minds become whole again",
            "then receive the night as permission to be off duty",
            "and let peaceful silence wrap around every lingering thought",
            "even when reflex says you should prepare for tomorrow",
            "because stopping is also a skill worth practicing well",
            "while sleep works overnight on your behalf",
            "and remember the weekend is still here tonight",
            "instead of spending the dark hours performing readiness",
            "so you wake restored rather than merely paused",
            "trusting that deep rest is never laziness",
            "then dream freely without carrying the week into bed",
            "and allow the night to restore what effort cannot",
        ],
        "closings": [
            "Sweet dreams are earned.",
            "Rest well tonight.",
            "Tomorrow can wait for now.",
            "Let the night hold you gently.",
            "That is enough for today.",
        ],
    },
}


def _compose_quote(
    phrases: dict[str, list[str]],
    rng: random.Random,
    qualifier: str | None = None,
) -> str:
    opening = rng.choice(phrases["openings"])
    middle = rng.choice(phrases["middles"])
    closing = rng.choice(phrases["closings"])
    body = f"{opening}, {middle[0].lower()}{middle[1:]}, {closing[0].lower()}{closing[1:]}"
    if qualifier:
        body = f"{qualifier} {body[0].lower()}{body[1:]}"
    return body


def expand_templates(
    templates: list[str],
    target: int,
    rng: random.Random,
    day: str,
    period: str,
    *,
    leisure: bool,
) -> list[str]:
    seen: set[str] = set()
    quotes: list[str] = []
    for template in templates:
        if template not in seen:
            seen.add(template)
            quotes.append(template)

    qualifiers = DAY_QUALIFIERS.get(day, {}).get(period, [])
    phrase_bank = LEISURE_PHRASES if leisure else WORK_PHRASES
    attempts = 0
    max_attempts = target * 400

    while len(quotes) < target and attempts < max_attempts:
        attempts += 1
        roll = rng.random()
        variant: str

        if roll < 0.35:
            qualifier = rng.choice(qualifiers) if qualifiers and rng.random() < 0.6 else None
            variant = _compose_quote(phrase_bank[period], rng, qualifier)
        elif roll < 0.50:
            base = rng.choice(templates)
            if qualifiers and rng.random() < 0.5:
                qualifier = rng.choice(qualifiers)
                body = base[0].lower() + base[1:] if base else base
                variant = f"{qualifier} {body}"
            else:
                variant = base
        elif roll < 0.62:
            base = rng.choice(templates)
            opener = rng.choice(OPENERS)
            body = base[0].lower() + base[1:] if base else base
            variant = f"{opener} {body}"
        elif roll < 0.74:
            base = rng.choice(templates)
            variant = base.rstrip(".") + rng.choice(CLOSERS)
        elif roll < 0.86:
            base = rng.choice(templates)
            variant = base.rstrip(".") + " —" + rng.choice(TAILS)
        else:
            qualifier = rng.choice(qualifiers) if qualifiers else None
            variant = _compose_quote(phrase_bank[period], rng, qualifier)
            if rng.random() < 0.4:
                variant = f"{rng.choice(OPENERS)} {variant[0].lower()}{variant[1:]}"

        if MIN_LENGTH <= len(variant) <= MAX_LENGTH and variant not in seen:
            seen.add(variant)
            quotes.append(variant)

    if len(quotes) < target:
        raise RuntimeError(f"{day}.{period}: only generated {len(quotes)} of {target} quotes")

    return quotes[:target]


def generate_day(day: str, rng: random.Random) -> dict[str, list[str]]:
    leisure = day not in WORK_DAYS
    base = WEEKDAY_TEMPLATES if not leisure else LEISURE_TEMPLATES
    return {
        period: expand_templates(base[period], QUOTES_PER_SET, rng, day, period, leisure=leisure)
        for period in PERIODS
    }


def main() -> None:
    payload: dict[str, dict[str, list[str]]] = {}
    for day in (*WORK_DAYS, *LEISURE_DAYS):
        day_rng = random.Random(f"{day}-quotes-v2")
        payload[day] = generate_day(day, day_rng)

    for day in payload:
        for period in PERIODS:
            quotes = payload[day][period]
            assert len(quotes) == QUOTES_PER_SET, f"{day}.{period} has {len(quotes)} quotes"
            assert len(set(quotes)) == QUOTES_PER_SET, f"{day}.{period} has duplicate quotes"
            lengths = [len(q) for q in quotes]
            assert min(lengths) >= MIN_LENGTH, f"{day}.{period} min length {min(lengths)}"
            assert max(lengths) <= MAX_LENGTH, f"{day}.{period} max length {max(lengths)}"

    for output in OUTPUT_PATHS:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        total = len(PERIODS) * QUOTES_PER_SET * len(payload)
        print(f"Wrote {total} quotes -> {output}")


if __name__ == "__main__":
    main()
