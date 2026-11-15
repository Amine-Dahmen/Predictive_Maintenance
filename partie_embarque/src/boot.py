# Runs before main.py at every boot. Not updated over the air: it is the safety
# net of the remote firmware update (US-46).
# While a new version is waiting for confirmation, a hardware watchdog resets
# the board if main.py crashes or hangs; after ota.MAX_BOOTS failed boots the
# previous files are restored.
try:
    import ota
    state = ota.boot_check()
    if state == "pending":
        from machine import WDT
        WDT(timeout=120000)  # fed by main.py; unfed (crash at import) -> reset -> counted here
        print("ota: new firmware on trial")
    elif state == "rollback":
        print("ota: previous firmware restored")
except Exception as e:  # never prevent the board from booting
    print("boot: ota check skipped (%r)" % e)
