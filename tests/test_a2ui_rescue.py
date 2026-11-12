"""The reply-text safety net, on a scripted Agent Framework update stream."""

import asyncio
import json

from agent_framework import ChatResponseUpdate, Content
from currency_agent.a2ui_rescue import PAYLOAD_ARG, TOOL_NAME, rescue_updates


def _run(chunks):
    async def source():
        for c in chunks:
            yield ChatResponseUpdate(role="assistant", contents=[Content.from_text(c)])

    async def collect():
        return [u async for u in rescue_updates(source())]

    updates = asyncio.run(collect())
    text = "".join(c.text for u in updates for c in u.contents if c.type == "text")
    calls = [c for u in updates for c in u.contents if c.type == "function_call"]
    return text, calls


def test_plain_text_passes_through():
    text, calls = _run(["Hello ", "there, 1 USD ", "is 0.9 EUR."])
    assert text == "Hello there, 1 USD is 0.9 EUR."
    assert calls == []


def test_a2ui_block_becomes_a_tool_call_and_leaves_the_chat():
    text, calls = _run(
        ["Here you go: <a2", 'ui>\nroot = RateCard("USD", "EUR", 1)\n', "</a2ui>"]
    )
    assert text == "Here you go: "
    assert len(calls) == 1
    assert calls[0].name == TOOL_NAME
    args = json.loads(calls[0].arguments)
    assert args[PAYLOAD_ARG].startswith("<a2ui>") and args[PAYLOAD_ARG].endswith(
        "</a2ui>"
    )


def test_unclosed_block_is_closed():
    _, calls = _run(['<a2ui>\nroot = RateCard("USD", "EUR", 1)'])
    assert json.loads(calls[0].arguments)[PAYLOAD_ARG].rstrip().endswith("</a2ui>")


def test_two_blocks_two_calls():
    _, calls = _run(["<a2ui>a</a2ui> and <a2ui>b</a2ui>"])
    assert len(calls) == 2


def test_partial_marker_that_is_not_a2ui_is_released():
    text, calls = _run(["a <a", "b> c"])
    assert text == "a <ab> c"
    assert calls == []
