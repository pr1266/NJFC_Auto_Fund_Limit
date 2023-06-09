import csv
import re
from datetime import datetime, timedelta
from os import path

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.action_chains import ActionChains

from dateutil.tz import gettz
from bs4 import BeautifulSoup
from selenium.common.exceptions import NoSuchElementException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as ec
from selenium.webdriver.support.ui import Select
from selenium.webdriver.support.wait import WebDriverWait

import time as mytime

DRIVER_PATH = "/home/mahdi/Projects/expert/ForexFactoryScrap/chromedriver.exe"
from selenium.webdriver.chrome.service import Service



class ForexFactory(webdriver.Chrome):
   def __init__(self, teardown=True):
      self.treardown = teardown
      options = Options()
      options.headless = False
      options.add_argument("--window-size=1920,1080")
      super(ForexFactory, self).__init__(options=options)
      self.implicitly_wait(60)
      self.maximize_window()
      self.action = ActionChains(self)

      # you can use the with-as structure to close the browser
   
   def __exit__(self, exc_type, exc_value, exc_tb):
      if self.treardown:
            self.quit()


   def get_start_dt(self, ff_timezone):
      """Get the start datetime for the scraping. Function incremental.

      Returns:
         datetime: The start datetime.
      """
      if path.isfile('forex_factory_catalog.csv'):
         with open('forex_factory_catalog.csv', 'rb+') as file:
               file.seek(0, 2)
               file_size = remaining_size = file.tell() - 2
               if file_size > 0:
                  file.seek(-2, 2)
                  while remaining_size > 0:
                     if file.read(1) == b'\n':
                           return datetime.fromisoformat(file.readline()[:25].decode())
                     file.seek(-2, 1)
                     remaining_size -= 1
                  file.seek(0)
                  file.truncate(0)
      return datetime(year=2007, month=1, day=1, hour=0, minute=0, tzinfo=ff_timezone)


      
   def dt_to_url(self, date):
      """Creates an url from a datetime

      Args:
         date (datetime): The datetime.

      Returns:
         str: The url.
      """
      if self.dt_is_start_of_month(date) and self.dt_is_complete(date, mode='month'):
         return 'calendar.php?month={}'.format(self.dt_to_str(date, mode='month'))
      if self.dt_is_start_of_week(date) and self.dt_is_complete(date, mode='week'):
         for weekday in [date + timedelta(days=x) for x in range(7)]:
               if self.dt_is_start_of_month(weekday) and self.dt_is_complete(date, mode='month'):
                  return 'calendar.php?day={}'.format(self.dt_to_str(date, mode='day'))
         return 'calendar.php?week={}'.format(self.dt_to_str(date, mode='week'))
      if self.dt_is_complete(date, mode='day') or self.dt_is_today(date):
         return 'calendar.php?day={}'.format(self.dt_to_str(date, mode='day'))
      raise ValueError('{} is not completed yet.'.format(self.dt_to_str(date, mode='day')))


   def dt_to_str(self, date, mode):
      if mode == 'month':
         return date.strftime('%b.%Y').lower()
      if mode in ('week', 'day'):
         return '{d:%b}{d.day}.{d:%Y}'.format(d=date).lower()
      raise ValueError('{} is not a proper mode; please use month, week, or day.'.format(mode))



   def get_mode(self, url):
      reg = re.compile('(?<=\\?).*(?=\\=)')
      return reg.search(url).group()


   def dt_is_complete(self, date, mode):
      return self.get_next_dt(date, mode) <= datetime.now(tz=date.tzinfo)


   def dt_is_start_of_week(self, date):
      return date.isoweekday() % 7 == 0


   def dt_is_start_of_month(self, date):
      return date.day == 1


   def dt_is_today(self, date):
      today = datetime.now()
      return today.year == date.year and today.month == date.month and today.day == date.day



   def get_next_dt(self, date, mode):
      """Calculate the next datetime to scrape from. Based on efficiency either a day, week start or
      month start.

      Args:
         date (datetime): The current datetime.
         mode (str): The operating mode; can be 'day', 'week' or 'month'.

      Returns:
         datetime: The new datetime.
      """
      if mode == 'month':
         (year, month) = divmod(date.month, 12)
         return date.replace(year=date.year + year, month=month + 1, day=1, hour=0, minute=0)
      if mode == 'week':
         return date.replace(hour=0, minute=0) + timedelta(days=7)
      if mode == 'day':
         return date.replace(hour=0, minute=0) + timedelta(days=1)
      raise ValueError('{} is not a proper mode; please use month, week, or day.'.format(mode))




   def scrab(self, start_date, ff_timezone):
      try:
         fields = ['date', 'time', 'currency', 'impact', 'event', 'actual', 'forecast', 'previous']
         mytime.sleep(1)
         try:
               date_url = self.dt_to_url(start_date)
         except ValueError:
               print('Successfully retrieved data')
               return
         print('\r' + 'Scraping data for link: ' + date_url, end='', flush=True)

         self.get('https://www.forexfactory.com/' + date_url)
         soup = BeautifulSoup(self.page_source, 'lxml')
         table = soup.find('table', class_='calendar__table')
         table_rows = table.select('tr.calendar__row.calendar_row')
         date = None
         for table_row in table_rows:
            try:
               currency, impact, event, actual, forecast, previous = '', '', '', '', '', ''
               for field in fields:
                  data = table_row.select('td.calendar__cell.calendar__{0}.{0}'.format(field))[0]
                  if field == 'date' and data.text.strip() != '':
                        day = data.text.strip().replace('\n', '')
                        if date is None:
                           year = str(start_date.year)
                        else:
                           year = str(self.get_next_dt(date, mode='day').year)
                        date = datetime.strptime(','.join([year, day]), '%Y,%a%b %d') \
                           .replace(tzinfo=ff_timezone)
                  elif field == 'time' and data.text.strip() != '':
                        time = data.text.strip()
                        if 'Day' in time:
                           date = date.replace(hour=23, minute=59, second=59)
                        elif 'Data' in time:
                           date = date.replace(hour=0, minute=0, second=1)
                        else:
                           i = 1 if len(time) == 7 else 0
                           date = date.replace(
                              hour=int(time[:1 + i]) % 12 + (12 * (time[4 + i:] == 'pm')),
                              minute=int(time[2 + i:4 + i]), second=0)
                  elif field == 'currency':
                        currency = data.text.strip()
                  elif field == 'impact':
                        impact = data.find('span')['title']
                  elif field == 'event':
                        event = data.text.strip()
                  elif field == 'actual':
                        actual = data.text.strip()
                  elif field == 'forecast':
                        forecast = data.text.strip()
                  elif field == 'previous':
                        previous = data.text.strip()
               if date.second == 1:
                  raise ValueError
               if date <= start_date:
                  continue
               if date >= datetime.now(tz=date.tzinfo):
                  break
               with open('forex_factory_catalog.csv', mode='a', newline='') as file:
                  writer = csv.writer(file, delimiter=',')
                  writer.writerow(
                        [str(date.astimezone(ff_timezone)), currency, impact, event, actual, forecast, previous]
                  )
            except TypeError:
               with open('errors.csv', mode='a') as file:
                  file.write(str(date) + ' (No Event Found)\n')


      except Exception as e:
         print(e)
      return date_url