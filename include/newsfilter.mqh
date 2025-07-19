//+------------------------------------------------------------------+
//| NewsFilter.mqh - Trading Time & News Filter                     |
//|                        Copyright 2025, Smartphone_FVG_Bot        |
//|                                    https://www.example.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Smartphone_FVG_Bot"
#property link      "https://www.example.com"
#property strict

class NewsFilter
{
private:
    // High-impact economic events
    static const string HighImpactEvents[5];
    
    // Trading session hours (adjust to your broker's local time)
    static const int marketOpenHour = 2;   // 02:00 AM
    static const int marketCloseHour = 20; // 08:00 PM
    
public:
    static bool IsSafeToTrade(datetime testTime = 0)
    {
        MqlDateTime dt;
        
        // Use current time if no test time provided
        if(testTime == 0) 
            TimeCurrent(dt);
        else
            TimeToStruct(testTime, dt);
        
        // Block all weekend trading (Saturday and Sunday)
        if(dt.day_of_week == SATURDAY || dt.day_of_week == SUNDAY) {
            return false;
        }
        
        // Block 1 hour after market open
        if(IsAfterOpenPeriod(dt)) {
            return false;
        }
        
        // Block 1 hour before market close
        if(IsBeforeClosePeriod(dt)) {
            return false;
        }
        
        // Check for high-impact news events
        for(int i = 0; i < 5; i++) {
            if(IsEventTime(HighImpactEvents[i], dt)) {
                return false;
            }
        }
        
        return true;
    }

private:
    // Block 1 hour after market open (02:00 AM - 03:00 AM)
    static bool IsAfterOpenPeriod(MqlDateTime &dt)
    {
        if(dt.day_of_week >= MONDAY && dt.day_of_week <= FRIDAY) {
            if(dt.hour == marketOpenHour) {
                return true;
            }
        }
        return false;
    }
    
    // Block 1 hour before market close (07:00 PM - 08:00 PM)
    static bool IsBeforeClosePeriod(MqlDateTime &dt)
    {
        if(dt.day_of_week >= MONDAY && dt.day_of_week <= FRIDAY) {
            if(dt.hour == marketCloseHour - 1) {
                return true;
            }
        }
        return false;
    }

    static bool IsEventTime(string eventName, MqlDateTime &dt)
    {
        // NFP (First Friday of month at 14:30)
        if(eventName == "NFP") {
            if(dt.day_of_week == FRIDAY && dt.day <= 7) {
                if((dt.hour == 14 && dt.min >= 30) || 
                   (dt.hour == 15 && dt.min <= 30)) {
                    return true;
                }
            }
        }
        
        // FOMC (Wednesday at 19:00)
        if(eventName == "FOMC") {
            if(dt.day_of_week == WEDNESDAY) {
                if((dt.hour == 18 && dt.min >= 45) || 
                   (dt.hour == 19 && dt.min <= 15)) {
                    return true;
                }
            }
        }
        
        // CPI (Monthly at 13:30)
        if(eventName == "CPI") {
            if(dt.day <= 15) { // Mid-month release
                if((dt.hour == 13 && dt.min >= 15) || 
                   (dt.hour == 14 && dt.min <= 15)) {
                    return true;
                }
            }
        }
        
        // Interest Rate (Thursday at 14:00)
        if(eventName == "Interest Rate") {
            if(dt.day_of_week == THURSDAY) {
                if((dt.hour == 13 && dt.min >= 45) || 
                   (dt.hour == 14 && dt.min <= 15)) {
                    return true;
                }
            }
        }
        
        // GDP (Monthly at 13:30)
        if(eventName == "GDP") {
            if(dt.day >= 25) { // End-of-month release
                if((dt.hour == 13 && dt.min >= 15) || 
                   (dt.hour == 14 && dt.min <= 15)) {
                    return true;
                }
            }
        }
        
        return false;
    }
};

// Define high-impact economic events
const string NewsFilter::HighImpactEvents[5] = 
{
    "NFP", "FOMC", "CPI", "Interest Rate", "GDP"
};