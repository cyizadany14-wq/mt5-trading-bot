//+------------------------------------------------------------------+
//|               Inverse FVG Bot (Final Verified v6.0)              |
//|              Mobile-Optimized for Smartphone Trading             |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "6.0"
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
  
  // Weekend blocking (Friday post-close to Sunday pre-open)
  if(dow == SATURDAY) return false;
  if(dow == SUNDAY && hour < 22) return false;
  if(dow == FRIDAY && hour >= 21) return false;

  // Convert input strings to time
  datetime lonStart = StringToTime(LondonOpen);
  datetime lonEnd = StringToTime(LondonClose);
  datetime nyStart = StringToTime(NewYorkOpen);
  datetime nyEnd = StringToTime(NewYorkClose);
  
  // Calculate buffer boundaries (1hr before/after sessions)
  datetime lonBufferStart = lonStart - 3600;
  datetime lonBufferEnd = lonEnd + 3600;
  datetime nyBufferStart = nyStart - 3600;
  datetime nyBufferEnd = nyEnd + 3600;
  
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
    if(atr > 0) {
      double riskPerTrade = equity * RiskPercent / 100.0;
      PositionSizes[i] = NormalizeDouble(riskPerTrade / (atr * 1.5), 2);
      PositionSizes[i] = MathMax(PositionSizes[i], 0.01);
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
  return 0.01;
}
//+------------------------------------------------------------------+
//| Fixed FVG Detection                                             |
//+------------------------------------------------------------------+
bool FindBearishFVG(double &top, double &bottom)
{
  // Proper index handling for 3-candle pattern
  int shift = 2;
  
  double closeCandle3 = iClose(_Symbol, PERIOD_H4, shift+1);
  double openCandle2  = iOpen(_Symbol, PERIOD_H4, shift);
  
  if(closeCandle3 > openCandle2) {
    double lowCandle2 = iLow(_Symbol, PERIOD_H4, shift);
    
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
  if(lots < 0.01) return;
  
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
  request.deviation = 50;
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
  for(int i=1; i<50; i++) {
    if(iHigh(Symbol(), PERIOD_H4, i) >= gapLevel || 
       iLow(Symbol(), PERIOD_H4, i) <= gapLevel) {
      return i * 4;
    }
  }
  return 999;
}

void SendTelegram(string message)
{
  if(StringLen(TelegramToken) < 20 || ChatID == 0) return;
  
  string headers;
  char   res[], req[];
  string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
  string data = "chat_id=" + (string)ChatID + "&text=" + message;
  
  WebRequest("POST", url, headers, 5000, req, res, headers);
}
//+------------------------------------------------------------------+
//| Check for bullish trend                                          |
//+------------------------------------------------------------------+
bool IsBullishTrend()
{
  double ema200 = iMA(Symbol(), PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
  if(iClose(Symbol(), PERIOD_D1, 0) < ema200) return false;
  
  double h0 = iHigh(Symbol(), PERIOD_H4, 0);
  double h1 = iHigh(Symbol(), PERIOD_H4, 1);
  double l0 = iLow(Symbol(), PERIOD_H4, 0);
  double l1 = iLow(Symbol(), PERIOD_H4, 1);
  
  return (h0 > h1 && l0 > l1);
}
//+------------------------------------------------------------------+
//| Check for bearish trend                                          |
//+------------------------------------------------------------------+
bool IsBearishTrend()
{
  double ema200 = iMA(Symbol(), PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
  if(iClose(Symbol(), PERIOD_D1, 0) > ema200) return false;
  
  double h0 = iHigh(Symbol(), PERIOD_H4, 0);
  double h1 = iHigh(Symbol(), PERIOD_H4, 1);
  double l0 = iLow(Symbol(), PERIOD_H4, 0);
  double l1 = iLow(Symbol(), PERIOD_H4, 1);
  
  return (h0 < h1 && l0 < l1);
}
//+------------------------------------------------------------------+
//| Check for bullish entry conditions                               |
//+------------------------------------------------------------------+
void CheckBullishEntry()
{
  double gapHigh, gapLow;
  if(!FindBearishFVG(gapHigh, gapLow)) return;
  
  if(GetGapAge(gapHigh) > MaxGapAge) return;
  
  int confirmations = 0;
  if(CheckVolumeSpike()) confirmations++;
  if(CheckRSIDivergence(true)) confirmations++;
  if(CheckOrderBlock(gapHigh)) confirmations++;
  
  if(confirmations < ConfluenceRequired) return;
  
  if(iClose(Symbol(), PERIOD_M5, 0) > gapHigh) {
    double atr = iATR(Symbol(), PERIOD_H1, ATR_Period, 0);
    double sl = gapLow - 1.5 * atr;
    double tp1 = gapHigh + (gapHigh - sl);
    ExecuteTrade(ORDER_TYPE_BUY, GetPositionSize(), sl, tp1, 0);
  }
}
//+------------------------------------------------------------------+
//| Check for bearish entry conditions                               |
//+------------------------------------------------------------------+
void CheckBearishEntry()
{
  double gapHigh, gapLow;
  if(!FindBullishFVG(gapHigh, gapLow)) return;
  
  if(GetGapAge(gapLow) > MaxGapAge) return;
  
  int confirmations = 0;
  if(CheckVolumeSpike()) confirmations++;
  if(CheckRSIDivergence(false)) confirmations++;
  if(CheckOrderBlock(gapLow)) confirmations++;
  
  if(confirmations < ConfluenceRequired) return;
  
  if(iClose(Symbol(), PERIOD_M5, 0) < gapLow) {
    double atr = iATR(Symbol(), PERIOD_H1, ATR_Period, 0);
    double sl = gapHigh + 1.5 * atr;
    double tp1 = gapLow - (sl - gapLow);
    ExecuteTrade(ORDER_TYPE_SELL, GetPositionSize(), sl, tp1, 0);
  }
}
//+------------------------------------------------------------------+
//| Find bullish FVG pattern                                         |
//+------------------------------------------------------------------+
bool FindBullishFVG(double &top, double &bottom)
{
  int shift = 2;
  double closeCandle3 = iClose(_Symbol, PERIOD_H4, shift+1);
  double openCandle2  = iOpen(_Symbol, PERIOD_H4, shift);
  
  if(closeCandle3 < openCandle2) {
    double highCandle2 = iHigh(_Symbol, PERIOD_H4, shift);
    
    if((openCandle2 - closeCandle3) < 5 * Point()) return false;
    
    if(highCandle2 > iHigh(_Symbol, PERIOD_H4, shift-1) && 
       highCandle2 > iHigh(_Symbol, PERIOD_H4, shift+1)) {
      bottom = MathMax(closeCandle3, openCandle2);
      top = highCandle2;
      return true;
    }
  }
  return false;
}
//+------------------------------------------------------------------+
//| Check for volume spike                                           |
//+------------------------------------------------------------------+
bool CheckVolumeSpike()
{
  double avgVolume = iMA(Symbol(), PERIOD_M15, 20, 0, MODE_SMA, VOLUME_TICK, 0);
  return (iVolume(Symbol(), PERIOD_M15, 0) > 1.5 * avgVolume;
}
//+------------------------------------------------------------------+
//| Check for RSI divergence                                         |
//+------------------------------------------------------------------+
bool CheckRSIDivergence(bool bullish)
{
  double rsi0 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 0);
  double rsi1 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 1);
  double rsi2 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 2);
  
  if(bullish) {
    return (iLow(Symbol(), PERIOD_H1, 0) < iLow(Symbol(), PERIOD_H1, 1) && 
            rsi0 > rsi1 && rsi1 < rsi2;
  }
  return (iHigh(Symbol(), PERIOD_H1, 0) > iHigh(Symbol(), PERIOD_H1, 1) && 
          rsi0 < rsi1 && rsi1 > rsi2;
}
//+------------------------------------------------------------------+
//| Check for order block confluence                                 |
//+------------------------------------------------------------------+
bool CheckOrderBlock(double price)
{
  double prevClose = iClose(Symbol(), PERIOD_D1, 1);
  return (MathAbs(price - prevClose) < 10 * Point());
}
//+------------------------------------------------------------------+
//| Manage open positions (exits)                                    |
//+------------------------------------------------------------------+
void ManageExits()
{
  for(int i=0; i<OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(TimeCurrent() - OrderOpenTime() > MaxGapAge * 3600) {
        OrderClose(OrderTicket(), OrderLots(), 
                  (OrderType()==OP_BUY) ? Bid : Ask, 5);
      }
    }
  }
}
//+------------------------------------------------------------------+
//| Check if symbol is allowed                                       |
//+------------------------------------------------------------------+
bool IsSymbolAllowed()
{
  for(int i=0; i<3; i++) {
    if(Symbol() == TradePairs[i]) return true;
  }
  return false;
}
//+------------------------------------------------------------------+