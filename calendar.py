import time
from ForexFactory.forexFactory import ForexFactory

timezone = "(GMT+00:00) UTC"


inst = ForexFactory()
start_date = inst.get_start_dt(timezone)
inst.quit()
while True:
    time.sleep(1)
    inst = ForexFactory()
    date_url = inst.scrab(start_date, timezone)
    start_date = inst.get_next_dt(start_date, mode=inst.get_mode(date_url))
    inst.quit()