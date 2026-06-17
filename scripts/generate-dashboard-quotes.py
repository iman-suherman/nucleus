#!/usr/bin/env python3
"""Generate DashboardQuotes.json — inspirational quotes without time-of-day words."""

from __future__ import annotations

import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "app/Nucleus/Resources/DashboardQuotes.json"
TARGET_COUNT = 10_000

TIME_OF_DAY = re.compile(
    r"\b("
    r"morning|afternoon|evening|night|midnight|dawn|dusk|noon|"
    r"sunrise|sunset|daybreak|twilight|nightfall|midday"
    r")\b",
    re.IGNORECASE,
)

ADJECTIVES = [
    "calm", "steady", "gentle", "kind", "warm", "bright", "clear", "simple",
    "quiet", "peaceful", "hopeful", "joyful", "curious", "bold", "patient",
    "focused", "grounded", "refreshing", "uplifting", "harmonious", "radiant",
    "cozy", "serene", "playful", "thoughtful", "mindful", "generous", "graceful",
    "resilient", "nimble", "delightful", "honest", "meaningful", "balanced",
    "confident", "open", "soft", "deep", "lasting", "effortless", "sparkling",
    "determined", "restful", "lovely", "thankful", "wise", "creative", "lighthearted",
    "productive", "sunny", "fresh", "renewed", "helpful", "steady", "earnest",
]

NOUNS = [
    "clarity", "focus", "momentum", "progress", "insight", "laughter", "calm",
    "peace", "rest", "warmth", "grace", "hope", "courage", "strength", "energy",
    "joy", "patience", "kindness", "gratitude", "wonder", "delight", "balance",
    "ease", "confidence", "light", "spark", "growth", "comfort", "honesty",
    "momentum", "priorities", "breath", "pause", "vision", "purpose", "presence",
    "momentum", "soft landings", "quiet wins", "small victories", "deep breaths",
    "gentle reminders", "bright ideas", "good surprises", "honest progress",
    "meaningful work", "helpful connections", "clear priorities", "simple pleasures",
    "renewed energy", "steady kindness", "lasting warmth", "playful patience",
]

CONTEXTS = [
    "focus", "step", "path", "habit", "routine", "moment", "pause", "week", "plan",
    "goal", "flow", "journey", "effort", "workspace", "conversation", "connection",
    "idea", "mind", "spirit", "heart", "progress", "balance", "thought", "dream",
    "vision", "rhythm", "practice", "direction", "intention", "workspace",
]

TEMPLATES = [
    "May {adj1} {noun1} find you in a {adj2} {ctx}.",
    "Trust the {adj1} rhythm of your {ctx}.",
    "Let {noun1} guide your {ctx}.",
    "Wishing you {adj1} {noun1} throughout your {ctx}.",
    "Hope {adj1} {noun1} follows you all {ctx} long.",
    "May every {ctx} bring you {adj1} {noun1}.",
    "Small {noun1} can change a whole {ctx}.",
    "You deserve a {adj1} {ctx} today.",
    "Keep your {ctx} {adj1} and your heart open.",
    "Choose {adj1} {noun1} over hurry.",
    "Take one {adj1} step at a time.",
    "Here's to a {adj1} {ctx} full of {noun1}.",
    "Sending wishes for a {adj1} {noun1} and gentle {noun2}.",
    "May your {ctx} unfold with {adj1} {noun1}.",
    "Every {adj1} {ctx} begins with one kind choice.",
    "May you carry {adj1} {noun1} into every {ctx}.",
    "Let this {ctx} be {adj1}, steady, and full of {noun1}.",
    "May {noun1} meet you where you are.",
    "Wishing you {adj1} moments and lasting {noun1}.",
    "Hope your {ctx} is {adj1} and full of {noun1}.",
    "May small {noun1} make your {ctx} feel {adj1}.",
    "Let {adj1} {noun1} guide your {ctx}.",
    "Your {ctx} is allowed to be {adj1}.",
    "May every {noun1} bring you {adj1} {noun2}.",
    "Wishing you a {adj1} {ctx} ahead.",
    "Choose {adj1} {noun1} over noise.",
    "May {adj1} {noun1} find you along the way.",
    "Trust the {adj1} pace of your {ctx}.",
    "Let steady {noun1} shape your {ctx}.",
    "May your {ctx} be filled with {adj1} {noun1}.",
    "Hope {adj1} {noun1} stays close to your {ctx}.",
    "Wishing you {adj1} {noun1} in every {ctx}.",
    "May you find {adj1} {noun1} in the smallest {ctx}.",
    "Carry {adj1} {noun1} with you through each {ctx}.",
    "Let {noun1} soften your {ctx}.",
    "May {adj1} {noun1} brighten your {ctx}.",
    "Give yourself permission for a {adj1} {ctx}.",
    "One {adj1} {noun1} can reshape your whole {ctx}.",
    "May your {ctx} grow with {adj1} {noun1}.",
    "Stay {adj1}; let {noun1} lead your {ctx}.",
]


def pick(rng: random.Random, items: list[str]) -> str:
    return rng.choice(items)


def fix_articles(quote: str) -> str:
    def replace_article(match: re.Match[str]) -> str:
        word = match.group(2)
        article = "an" if word[0].lower() in "aeiou" else "a"
        prefix = match.group(1)
        if prefix[0].isupper():
            article = article.capitalize()
        return f"{article} {word}"

    quote = re.sub(r"\b(A|a|An|an)\s+(\w+)", replace_article, quote)
    return quote


def has_article_error(quote: str) -> bool:
    if re.search(r"\ba [aeiou]", quote, re.IGNORECASE):
        return True
    if re.search(r"\ban [^aeiou]", quote, re.IGNORECASE):
        return True
    return False


def render(rng: random.Random) -> str:
    adj1 = pick(rng, ADJECTIVES)
    adj2 = pick(rng, ADJECTIVES)
    while adj2 == adj1:
        adj2 = pick(rng, ADJECTIVES)
    noun1 = pick(rng, NOUNS)
    noun2 = pick(rng, NOUNS)
    while noun2 == noun1:
        noun2 = pick(rng, NOUNS)
    ctx = pick(rng, CONTEXTS)
    template = pick(rng, TEMPLATES)
    quote = template.format(adj1=adj1, adj2=adj2, noun1=noun1, noun2=noun2, ctx=ctx)
    quote = fix_articles(quote)
    return quote[0].upper() + quote[1:]


def is_valid(quote: str) -> bool:
    if TIME_OF_DAY.search(quote):
        return False
    if has_article_error(quote):
        return False
    if not quote.endswith("."):
        return False
    if len(quote) < 24 or len(quote) > 120:
        return False
    return True


def generate_quotes(count: int, seed: int = 42) -> list[str]:
    rng = random.Random(seed)
    seen: set[str] = set()
    quotes: list[str] = []

    attempts = 0
    max_attempts = count * 50
    while len(quotes) < count and attempts < max_attempts:
        attempts += 1
        quote = render(rng)
        if not is_valid(quote):
            continue
        key = quote.lower()
        if key in seen:
            continue
        seen.add(key)
        quotes.append(quote)

    if len(quotes) < count:
        raise RuntimeError(f"Only generated {len(quotes)} unique quotes after {attempts} attempts")

    return quotes


def main() -> None:
    quotes = generate_quotes(TARGET_COUNT)
    assert len(quotes) == TARGET_COUNT
    assert len(set(q.lower() for q in quotes)) == TARGET_COUNT
    assert not any(TIME_OF_DAY.search(q) for q in quotes)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(quotes, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote {len(quotes)} quotes → {OUTPUT}")


if __name__ == "__main__":
    main()
