#include <Arrays/ArrayObj.mqh>
#define USD_RANGE 0
#define USD_NO_TRADE 1
#define EUR_RANGE 2
#define EUR_NO_TRADE 3

CArrayObj *fund_list;
CArrayObj *time_list;

bool bank_holiday = false;
int us_session = 0;
int eur_session = 0;
extern int epsilon = 30;
extern int delay = 60;
int start_range = 0;
int end_range = 0;
int index = 0;

class fund_event : public CObject{
    public:
        string date;
        string time;
        string currency;
        string name;
        int year;
        int month;
        int day;
        int timestamp;
        
        fund_event(string d, string t, string c, string n, int y, int m, int d_, int ts): date(d), time(t), currency(c), name(n), year(y), month(m), day(d_), timestamp(ts){};
};

class time_range : public CObject{
    public:
        int start_range;
        int end_range;
        time_range(int s, int e): start_range(s), end_range(e){};
};

string sep = ",";                // A separator as a character
ushort u_sep;                  // The code of the separator character
string result[];               // An array to get strings\

string date_result[];
string date_sep = "-";
ushort u_date_sep;
string target_file_name = "clean_funds.csv";
int line_count = 0;

int OnInit(){
    fund_list = new CArrayObj;
    time_list = new CArrayObj;
    load_box();
    return(INIT_SUCCEEDED);
}

datetime NewCandleTime = TimeCurrent();
bool isNewCandle(){
    if(NewCandleTime == iTime(Symbol(), 0, 0)) return false;
    else{
        NewCandleTime = iTime(Symbol(), 0, 0);
        return true;
    }
}

void load_box(){    
    int k;
    int fd = FileOpen(target_file_name, FILE_READ|FILE_CSV|FILE_ANSI);
    while(!FileIsEnding(fd)){
        string to_split = FileReadString(fd);
        u_sep = StringGetCharacter(sep,0);
        k = StringSplit(to_split, u_sep, result); 
        string date, time, currency, name;
        if(k>0){            
            currency = (result[1]);
            name = (result[3]);            
            if(StringFind(ChartSymbol(), currency) == -1 && StringFind(name, "Bank Holiday") == -1) continue;            
            date = (result[4]);            
            u_date_sep = StringGetCharacter(date_sep,0);
            int k_date = StringSplit(date, u_date_sep, date_result);            
            time = (result[5]);
            int year = StrToInteger(date_result[0]);
            if(year < Year()) continue;
            int month = StrToInteger(date_result[1]);
            int day = StrToInteger(date_result[2]);            
            string str_time = year + "." + month + "." + day + " " + time;
            int timestamp__ = StrToTime(str_time) + (delay * 60);
            fund_event* e = new fund_event(date, time, currency, name, year, month, day, timestamp__);
            fund_list.Insert(e, 0);
        }
    }
    FileClose(fd);
}

bool FundTimeCheck(){
    if(bank_holiday == 1) return false;
    if(time_list.Total() == 0) return true;
    time_range* temp;
    int time_current = iTime(NULL, 0, 0);
    for(int i = 0; i < time_list.Total(); i++){
        temp = time_list.At(i);
        if(time_current >= temp.start_range && time_current <= temp.end_range) return false;
    }
    return true;
}

void update_time_range(int mode, int ts){
    string start_time_str;
    string end_time_str;
    int start_time_ts;
    int end_time_ts;
    time_range* new_range;
    
    if(mode == EUR_NO_TRADE){
        //! inja bayad date ro dararim, range 9 sob ta 13 ro limit konim:
        start_time_str = Year() + "." + Month() + "." + Day() + " 9:00:00";
        start_time_ts = StrToTime(start_time_str);
        end_time_str = Year() + "." + Month() + "." + Day() + " 15:00:00";
        end_time_ts = StrToTime(end_time_str);
        new_range = new time_range(start_time_ts, end_time_ts);
        time_list.Insert(new_range, 0);
        return;
    }
    else if(mode == EUR_RANGE){
        //! inja epsilon:
        start_time_ts = ts - (epsilon * 60);
        end_time_ts = ts + (epsilon * 60);
        new_range = new time_range(start_time_ts, end_time_ts);
        time_list.Insert(new_range, 0);
        return;
    }

    else if(mode == USD_NO_TRADE){
        //! inja bayad date ro dararim, range 9 sob ta 13 ro limit konim:
        start_time_str = Year() + "." + Month() + "." + Day() + " 15:00:00";
        start_time_ts = StrToTime(start_time_str);
        end_time_str = Year() + "." + Month() + "." + Day() + " 20:00:00";
        end_time_ts = StrToTime(end_time_str);
        new_range = new time_range(start_time_ts, end_time_ts);
        time_list.Insert(new_range, 0);
        return;
    }
    else if(mode == USD_RANGE){
        //! inja epsilon:
        start_time_ts = ts - (epsilon * 60);
        end_time_ts = ts + (epsilon * 60);
        new_range = new time_range(start_time_ts, end_time_ts);
        time_list.Insert(new_range, 0);
        return;
    }
}

void update_fundamental(){
    CArrayObj* new_list = new CArrayObj;
    time_list.DeleteRange(0, time_list.Total());
    bank_holiday = 0;
    fund_event* temp;
    int j;
    int usd_news = 0;
    int prev_us_fund_time = 0;
    int prev_eur_fund_time = 0;
    string to_comment = "";
    
    for(j = fund_list.Total()-1; j >= 0; j--){        
        temp = fund_list.At(j);         
        if(temp.month == Month() && temp.day == Day()){
            new_list.Insert(temp, 0);
            if(temp.name == "Bank Holiday"){
                bank_holiday = 1;
            }
            else if(prev_us_fund_time == 0 && StringFind(temp.currency, "USD") != -1){
                us_session = 1;
                prev_us_fund_time = temp.timestamp;
            }
            
            else if(prev_eur_fund_time == 0 && StringFind(temp.currency, "EUR") != -1){
                eur_session = 1;
                prev_eur_fund_time = temp.timestamp;
            }
                        
            else{
                if(prev_us_fund_time != temp.timestamp && StringFind(temp.currency, "USD") != -1){
                    us_session = 2;                   
                }
               
                else if(prev_eur_fund_time != temp.timestamp && StringFind(temp.currency, "EUR") != -1){
                    eur_session = 2;                    
                }
               
                else if(prev_us_fund_time == temp.timestamp && StringFind(temp.currency, "USD") != -1 && prev_us_fund_time != 2){
                    us_session = 1;
                    prev_us_fund_time = temp.timestamp;          
                }
               
                else if(prev_eur_fund_time == temp.timestamp && StringFind(temp.currency, "EUR") != -1 && prev_eur_fund_time != 2){
                    eur_session = 1;
                    prev_eur_fund_time = temp.timestamp;
                }
            }
        }
    }
    for(j = new_list.Total() - 1; j >= 0; j--){
        temp = new_list.At(j);
        //PrintFormat("currency : %s, name : %s, date : %s", temp.currency, temp.name, temp.date);
        to_comment += "currency : " + temp.currency + ", name : " + temp.name + ", date : " + temp.date + "\n";        
    }
    // int mode, int ts
    if(bank_holiday == 1){
        to_comment += "bank holiday, no trading today" + "\n";
    }

    if(eur_session == 2){
        to_comment += "no trading in eur session" + "\n";
        update_time_range(EUR_NO_TRADE, prev_eur_fund_time);
    }

    else if(eur_session == 1){
        to_comment += "eur session range " + TimeToStr(prev_eur_fund_time) + "\n";
        update_time_range(EUR_RANGE, prev_eur_fund_time);
    }

    else if(eur_session == 0){
        to_comment += "no traiding limits in eur session"+"\n";
    }

    if(us_session == 2){
        to_comment += "no trading in us session" + "\n";
        update_time_range(USD_NO_TRADE, prev_us_fund_time);
    }
    else if(us_session == 1){
        to_comment += "us session range " + TimeToStr(prev_us_fund_time) + "\n";
        update_time_range(USD_RANGE, prev_us_fund_time);
    }

    else if(us_session == 0){
        to_comment += "no traiding limits in us session"+"\n";
    }
    Comment(to_comment);
}

void update_rect(){
    time_range* temp;
    string name;
    if(bank_holiday == 1){
        return;
    }

    if(time_list.Total() == 0) return;
    for(int i = 0; i < time_list.Total(); i++){
        name = "Rectangle" + index++;
        temp = time_list.At(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, temp.start_range, 9999, temp.end_range, -1);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
    }
}

void OnTick(){
    if(isNewCandle()){
        if(Hour() == 1 && Minute() == 0){
            update_fundamental();
            Print(time_list.Total());
            update_rect();
        }        
    }
}