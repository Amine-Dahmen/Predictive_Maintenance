# Fixed-size FIFO for the measurements that could not be sent (US-45).
#
# While Wi-Fi or the broker is unreachable, main.py keeps one JSON message per
# cycle here and sends them, oldest first, once the link is back. When full,
# the oldest message is dropped, so a long outage keeps the most recent data.
#
# Pure Python (no machine module) so it also runs on the PC for unit tests.


class RingBuffer:
    def __init__(self, size):
        self.size = size
        self.items = [None] * size
        self.start = 0
        self.count = 0
        self.dropped = 0   # messages lost because the buffer was full

    def __len__(self):
        return self.count

    def push(self, item):
        if self.count == self.size:
            self.start = (self.start + 1) % self.size
            self.count -= 1
            self.dropped += 1
        self.items[(self.start + self.count) % self.size] = item
        self.count += 1

    def peek(self):
        """Oldest item, or None when empty."""
        return self.items[self.start] if self.count else None

    def pop(self):
        if not self.count:
            return None
        item = self.items[self.start]
        self.items[self.start] = None
        self.start = (self.start + 1) % self.size
        self.count -= 1
        return item
