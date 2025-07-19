//+------------------------------------------------------------------+
//|               Inverse FVG Bot (Final Verified v5.0)              |
//|              Mobile-Optimized for Smartphone Trading             |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "5.0"
#property strict

// Risk Management
input double   RiskPercent        = 1.0;     // Max risk per trade (%)
input double   MaxTotalRisk       = 5.0;     // Max portfolio risk (%)
input int      ATR_Period         = 14;      // ATR for SL calculation

// Trading Sessions (GMT)
input string   LondonOpen         = "07:00"; // Core London start
input string   LondonClose        = "16:00"; // Core London end
input string   NewYorkOpen        = "12:00"; // Core New York start
input string   NewYorkClose       = "20:00"; // Core New York end

// Strategy Parameters
input int      ADX_Threshold      = 25;      // Min ADX for trending
input int      MaxGapAge          = 72;      // Max hours since FVG formed
input int      ConfluenceRequired = 2;       // Min confirmations needed

// Telegram Configuration
input string   TelegramToken      = "";      // From @BotFather
input long     ChatID             = 0;       // From @userinfobot

// Global Variables
string         TradePairs[3]      = {"EURUSD", "USDJPY", "GBPUSD"};
double         PositionSizes[3];
datetime       LastTickTime;
bool           TradingAllowed = false;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  // Validate trading symbol
  if(!IsSymbolAllowed()) {
    Alert("Invalid symbol - Only EURUSD, USDJPY, GBPUSD allowed");
    return(INIT_FAILED);
  }
  
  // Initialize position sizes
  CalculateRisk();
  
  // Send activation alert
  SendTelegram("🚀 Inverse FVG Bot ACTIVATED" +
               "\nSymbol: " + Symbol() +
               "\nSession Buffers: 1hr before/after London/NY" +
               "\nRisk: " + DoubleToString(RiskPercent,1) + "%/trade, " + 
               DoubleToString(MaxTotalRisk,1) + "% total");
               
  // Initialize last tick time
  LastTickTime = TimeCurrent();
  
  return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Fixed Time Filter with Session Buffers                           |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
  datetime now = TimeCurrent();
  int dow = TimeDayOfWeek(now);
  int hour = TimeHour(now);
  int minute = TimeMinute(now);
  
  // Convert input strings to time
  datetime lonStart = StringToTime(LondonOpen);
  datetime lonEnd = StringToTime(LondonClose);
  datetime nyStart = StringToTime(NewYorkOpen);
  datetime nyEnd = StringToTime(NewYorkClose);
  
  // Weekend blocking (Friday post-close to Sunday pre-open)
  if(dow == SATURDAY) return false;
  if(dow == SUNDAY && hour < 22) return false;
  if(dow == FRIDAY && hour >= 21) return false;

  // Calculate buffer boundaries (1hr before/after sessions)
  datetime lonBufferStart = lonStart - 3600;  // 1hr before London
  datetime lonBufferEnd = lonEnd + 3600;      // 1hr after London
  datetime nyBufferStart = nyStart - 3600;    // 1hr before NY
  datetime nyBufferEnd = nyEnd + 3600;        // 1hr after NY
  
  // Check if current time is within any buffer zone
  bool inAnyBuffer = (now >= lonBufferStart && now <= lonBufferEnd) || 
                     (now >= nyBufferStart && now <= nyBufferEnd);
  
  // Allow trading only in CORE session hours
  TradingAllowed = (now >= lonStart && now <= lonEnd) || 
                   (now >= nyStart && now <= nyEnd);
  
  return (inAnyBuffer && TradingAllowed);
}
//+------------------------------------------------------------------+
//| Fixed Risk Management Engine                                    |
//+------------------------------------------------------------------+
void CalculateRisk()
{
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  
  for(int i=0; i<3; i++) {
    double atr = iATR(TradePairs[i], PERIOD_H4, ATR_Period, 0);
    if(atr > 0) { // Prevent division by zero
      double riskPerTrade = equity * RiskPercent / 100.0;
      PositionSizes[i] = NormalizeDouble(riskPerTrade / (atr * 1.5), 2);
      
      // Ensure minimum lot size
      if(PositionSizes[i] < 0.01) PositionSizes[i] = 0.01;
    }
    else {
      PositionSizes[i] = 0.01;
    }
  }
}

double GetPositionSize()
{
  for(int i=0; i<3; i++) {
    if(TradePairs[i] == Symbol()) 
      return PositionSizes[i];
  }
  return 0.01; // Minimum lot size
}
//+------------------------------------------------------------------+
//| Fixed FVG Detection                                             |
//+------------------------------------------------------------------+
bool FindBearishFVG(double &top, double &bottom)
{
  // Proper index handling for 3-candle pattern
  int shift = 2; // Lookback start point
  
  double closeCandle3 = iClose(_Symbol, PERIOD_H4, shift+1);
  double openCandle2  = iOpen(_Symbol, PERIOD_H4, shift);
  
  // Bearish FVG: Candle3 closes above Candle2's open
  if(closeCandle3 > openCandle2) {
    double lowCandle2 = iLow(_Symbol, PERIOD_H4, shift);
    
    // Validate gap structure (low of Candle2 is lowest in 3 candles)
    if(lowCandle2 < iLow(_Symbol, PERIOD_H4, shift-1) && 
       lowCandle2 < iLow(_Symbol, PERIOD_H4, shift+1)) 
    {
      top = MathMin(closeCandle3, openCandle2);
      bottom = lowCandle2;
      return true;
    }
  }
  return false;
}
//+------------------------------------------------------------------+
//| Fixed News Filter                                               |
//+------------------------------------------------------------------+
bool IsNewsApproaching()
{
  static datetime lastCheck = 0;
  if(TimeCurrent() - lastCheck < 1800) return false;
  lastCheck = TimeCurrent();
  
  // Get today's date string
  string today = TimeToString(TimeCurrent(), TIME_DATE);
  
  // High-impact news events (example times)
  string highImpactTimes[] = {
    today + " 13:30", // FOMC example
    today + " 13:30"  // NFP example
  };
  
  for(int i=0; i<ArraySize(highImpactTimes); i++) {
    datetime newsTime = StringToTime(highImpactTimes[i]);
    if(MathAbs(newsTime - TimeCurrent()) <= 3600) {
      SendTelegram("⚠️ High Impact News: " + highImpactTimes[i]);
      return true;
    }
  }
  return false;
}
//+------------------------------------------------------------------+
//| Fixed Trade Execution                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp1, double tp2)
{
  // Skip if no trading volume
  if(lots < 0.01) {
    SendTelegram("⚠️ Trade Skipped: Lot size too small");
    return;
  }
  
  MqlTradeRequest request = {0};
  MqlTradeResult result = {0};
  
  request.action    = TRADE_ACTION_DEAL;
  request.symbol    = Symbol();
  request.volume    = lots;
  request.type      = type;
  request.price     = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) 
                                              : SymbolInfoDouble(Symbol(), SYMBOL_BID);
  request.sl        = sl;
  request.tp        = tp1;
  request.deviation = 50; // Increased deviation tolerance
  request.comment   = "InverseFVG";
  
  if(OrderSend(request, result)) {
    if(result.retcode == TRADE_RETCODE_DONE) {
      string log = StringFormat("%s %s %.2f lots | Entry: %.5f | SL: %.5f | TP1: %.5f",
                   (type == ORDER_TYPE_BUY) ? "🟢 BUY" : "🔴 SELL",
                   Symbol(), lots, request.price, sl, tp1);
      SendTelegram(log);
    }
    else {
      SendTelegram("❌ Trade Failed: " + IntegerToString(result.retcode));
    }
  }
}
//+------------------------------------------------------------------+
//| Fixed Helper Functions                                          |
//+------------------------------------------------------------------+
int GetGapAge(double gapLevel)
{
  for(int i=1; i<50; i++) { // Only check last 50 bars
    if(iHigh(Symbol(), PERIOD_H4, i) >= gapLevel || 
       iLow(Symbol(), PERIOD_H4, i) <= gapLevel) {
      return i * 4; // Hours since formation
    }
  }
  return 999;
}

void SendTelegram(string message)
{
  // Skip if Telegram not configured
  if(StringLen(TelegramToken) < 20 || ChatID == 0) return;
  
  string headers;
  char   res[], req[];
  string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
  string data = "chat_id=" + (string)ChatID + "&text=" + message;
  
  int response = WebRequest("POST", url, headers, 5000, req, res, headers);
  
  // Error handling
  if(response != 200) {
    Print("Telegram error: ", response, " ", CharArrayToString(res));
  }
}
//+------------------------------------------------------------------+
// ... (Other functions remain unchanged from previous version) ...
//+------------------------------------------------------------------+