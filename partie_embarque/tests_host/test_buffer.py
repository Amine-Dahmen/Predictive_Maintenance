# Host-side unit tests for the offline message buffer (src/buffer.py, US-45).
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from buffer import RingBuffer  # noqa: E402


def test_fifo_order():
    b = RingBuffer(3)
    for i in range(3):
        b.push(i)
    assert len(b) == 3 and b.peek() == 0
    assert [b.pop(), b.pop(), b.pop(), b.pop()] == [0, 1, 2, None]
    assert len(b) == 0 and b.peek() is None


def test_full_buffer_drops_the_oldest():
    b = RingBuffer(3)
    for i in range(5):
        b.push(i)
    assert b.dropped == 2
    assert [b.pop() for _ in range(3)] == [2, 3, 4]


def test_wraps_around():
    b = RingBuffer(2)
    b.push("a"); b.push("b"); b.pop(); b.push("c")
    assert [b.pop(), b.pop()] == ["b", "c"]
