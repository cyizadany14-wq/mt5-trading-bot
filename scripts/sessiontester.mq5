//+------------------------------------------------------------------+
//|                                                      SessionTester.mq5 |
//|                        Copyright 2025, Smartphone_FVG_Bot        |
//|                                    https://www.example.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Smartphone_FVG_Bot"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict
#property script_show_inputs

#include <newsfilter.mqh>  // Include the news filter module

//--- Input Parameters
input ENUM_DAY_OF_WEEK TestDay = SUNDAY;   // Day to test
input int TestHour = 12;                   // Hour to test (0-23)
input int TestMinute = 0;                  // Minute to test (0-59)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    // Create test time structure
    MqlDateTime testTime;
    TimeCurrent(testTime);  // Start with current time
    
    // Override with test parameters
    testTime.day_of_week = TestDay;
    testTime.hour = TestHour;
    testTime.min = TestMinute;
    testTime.sec = 0;
    
    // Convert to datetime
    datetime testDate = StructToTime(testTime);
    
    // Test news filter
    bool isSafe = NewsFilter::IsSafeToTrade(testDate);
    
    // Display results
    string result = "Session Test Results:\n" +
                   "Time: " + TimeToString(testDate) + "\n" +
                   "Day: " + EnumToString(TestDay) + "\n" +
                   "Safe to Trade: " + (isSafe ? "YES" : "NO") + "\n\n" +
                   (isSafe ? "✓ Trading Allowed" : "✗ Avoid Trading - News/Risk Period");
    
    Comment(result);
    Print(result);
    
    // Visual alert
    if(!isSafe) Alert("High Risk Period Detected!");
}

//+------------------------------------------------------------------+
//| Convert MqlDateTime to datetime                                 |
//+------------------------------------------------------------------+
datetime StructToTime(MqlDateTime &dtStruct)
{
    return StringToTime(
        StringFormat("%04d.%02d.%02d %02d:%02d", 
        dtStruct.year, dtStruct.mon, dtStruct.day, 
        dtStruct.hour, dtStruct.min)
    );
}