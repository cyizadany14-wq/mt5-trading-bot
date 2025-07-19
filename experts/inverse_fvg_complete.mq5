//+------------------------------------------------------------------+
//|               Inverse FVG Bot with Session Buffers (v4.2)        |
//|              Mobile-Optimized for Smartphone Trading             |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "4.2"
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
               DoubleToString(MaxTotalRisk,1) + "% total" +
               "\nEquity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
               
  // Initialize last tick time
  LastTickTime = TimeCurrent();
  
  return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Enhanced Time Filter with Session Buffers                        |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
  datetime now = TimeCurrent();
  int dow = TimeDayOfWeek(now);
  int hour = TimeHour(now);
  int minute = TimeMinute(now);
  string timeStr = StringFormat("%02d:%02d", hour, minute);
  
  // Weekend blocking (Friday post-close to Sunday pre-open)
  if(dow == SATURDAY) return false;
  if(dow == SUNDAY && hour < 22) return false;
  if(dow == FRIDAY && hour >= 21) return false;

  // Parse session times
  int lonOpenH = (int)StringSubstr(LondonOpen, 0, 2);
  int lonOpenM = (int)StringSubstr(LondonOpen, 3, 2);
  int lonCloseH = (int)StringSubstr(LondonClose, 0, 2);
  int lonCloseM = (int)StringSubstr(LondonClose, 3, 2);
  
  int nyOpenH = (int)StringSubstr(NewYorkOpen, 0, 2);
  int nyOpenM = (int)StringSubstr(NewYorkOpen, 3, 2);
  int nyCloseH = (int)StringSubstr(NewYorkClose, 0, 2);
  int nyCloseM = (int)StringSubstr(NewYorkClose, 3, 2);
  
  // Calculate buffer boundaries (1hr before/after sessions)
  datetime lonStart = StringToTime(StringFormat("%02d:%02d", lonOpenH, lonOpenM));
  datetime lonEnd = StringToTime(StringFormat("%02d:%02d", lonCloseH, lonCloseM));
  datetime lonBufferStart = lonStart - 3600;  // 1hr before London
  datetime lonBufferEnd = lonEnd + 3600;      // 1hr after London
  
  datetime nyStart = StringToTime(StringFormat("%02d:%02d", nyOpenH, nyOpenM));
  datetime nyEnd = StringToTime(StringFormat("%02d:%02d", nyCloseH, nyCloseM));
  datetime nyBufferStart = nyStart - 3600;    // 1hr before NY
  datetime nyBufferEnd = nyEnd + 3600;        // 1hr after NY
  
  // Check if current time is within any buffer zone
  bool inLondonBuffer = (now >= lonBufferStart && now <= lonBufferEnd);
  bool inNewYorkBuffer = (now >= nyBufferStart && now <= nyBufferEnd);
  
  // Allow trading only in CORE session hours (excluding buffers)
  bool inLondonCore = (now >= lonStart && now <= lonEnd);
  bool inNewYorkCore = (now >= nyStart && now <= nyEnd);
  
  // Trading allowed only during core sessions
  TradingAllowed = (inLondonCore || inNewYorkCore);
  
  // Return true only if in buffer zone AND in core session
  return (inLondonBuffer || inNewYorkBuffer) ? TradingAllowed : false;
}
//+------------------------------------------------------------------+
//| Risk Management Engine                                           |
//+------------------------------------------------------------------+
void CalculateRisk()
{
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double riskPerTrade = equity * RiskPercent / 100.0;
  
  for(int i=0; i<3; i++) {
    double atr = iATR(TradePairs[i], PERIOD_H4, ATR_Period, 0);
    PositionSizes[i] = NormalizeDouble(riskPerTrade / (atr * 1.5), 2);
    
    // Ensure minimum lot size
    if(PositionSizes[i] < 0.01) PositionSizes[i] = 0.01;
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

bool IsRiskExceeded()
{
  double totalRisk = 0;
  for(int i=0; i<PositionsTotal(); i++) {
    if(PositionGetSymbol(i) == Symbol()) {
      double positionValue = PositionGetDouble(POSITION_VOLUME) * 
                             PositionGetDouble(POSITION_PRICE_OPEN);
      double positionRisk = (positionValue / AccountInfoDouble(ACCOUNT_EQUITY)) * 100;
      totalRisk += positionRisk;
    }
  }
  return (totalRisk >= MaxTotalRisk);
}
//+------------------------------------------------------------------+
//| News Event Filter (Simplified)                                   |
//+------------------------------------------------------------------+
bool IsNewsApproaching()
{
  static datetime lastCheck = 0;
  if(TimeCurrent() - lastCheck < 1800) return false; // Check every 30 min
  lastCheck = TimeCurrent();
  
  // High-impact news events (example times)
  string highImpactTimes[] = {
    "2023.12.15 13:30", // FOMC example
    "2023.12.08 13:30"  // NFP example
  };
  
  for(int i=0; i<ArraySize(highImpactTimes); i++) {
    datetime newsTime = StringToTime(highImpactTimes[i]);
    double timeDiff = MathAbs(newsTime - TimeCurrent());
    if(timeDiff <= 3600) { // 1hr before/after
      SendTelegram("⚠️ High Impact News: " + highImpactTimes[i]);
      return true;
    }
  }
  return false;
}
//+------------------------------------------------------------------+
//| Core Strategy Implementation                                     |
//+------------------------------------------------------------------+
void OnTick()
{
  // Skip if not trading time or news approaching
  if(!IsTradingTime() || IsNewsApproaching()) {
    if(TradingAllowed) SendTelegram("⏸ Trading Paused (Session Buffer/News)");
    return;
  }
  
  // Throttle processing (every 5 minutes)
  if(TimeCurrent() - LastTickTime < 300) return;
  LastTickTime = TimeCurrent();
  
  // Skip in non-trending markets
  if(iADX(Symbol(), PERIOD_H4, 14, PRICE_CLOSE, MODE_MAIN, 0) < ADX_Threshold) {
    Comment("Market Sideways (ADX < ", ADX_Threshold, ")");
    return;
  }
  
  // Check risk limits
  if(IsRiskExceeded()) {
    SendTelegram("⛔ Max Risk Limit: " + DoubleToString(MaxTotalRisk,1) + "% reached");
    Comment("Risk Limit Exceeded");
    return;
  }
  
  // Execute strategy logic
  if(IsBullishTrend()) CheckBullishEntry();
  if(IsBearishTrend()) CheckBearishEntry();
  
  // Manage open positions
  ManageExits();
  
  // Update chart comment
  Comment("Inverse FVG Bot Active\n",
          "Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2), "\n",
          "Session: ", TradingAllowed ? "TRADING" : "CLOSED");
}

bool IsBullishTrend()
{
  // Price above 200 EMA on Daily
  double ema200 = iMA(Symbol(), PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
  if(iClose(Symbol(), PERIOD_D1, 0) < ema200) return false;
  
  // Higher Highs/Higher Lows on H4
  double h0 = iHigh(Symbol(), PERIOD_H4, 0);
  double h1 = iHigh(Symbol(), PERIOD_H4, 1);
  double l0 = iLow(Symbol(), PERIOD_H4, 0);
  double l1 = iLow(Symbol(), PERIOD_H4, 1);
  
  return (h0 > h1 && l0 > l1);
}

bool IsBearishTrend()
{
  // Price below 200 EMA on Daily
  double ema200 = iMA(Symbol(), PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
  if(iClose(Symbol(), PERIOD_D1, 0) > ema200) return false;
  
  // Lower Highs/Lower Lows on H4
  double h0 = iHigh(Symbol(), PERIOD_H4, 0);
  double h1 = iHigh(Symbol(), PERIOD_H4, 1);
  double l0 = iLow(Symbol(), PERIOD_H4, 0);
  double l1 = iLow(Symbol(), PERIOD_H4, 1);
  
  return (h0 < h1 && l0 < l1);
}

void CheckBullishEntry()
{
  double gapHigh, gapLow;
  if(!FindBearishFVG(gapHigh, gapLow)) return;
  
  // Validate FVG age
  if(GetGapAge(gapHigh) > MaxGapAge) return;
  
  // Confluence checks
  int confirmations = 0;
  if(CheckVolumeSpike()) confirmations++;
  if(CheckRSIDivergence(true)) confirmations++;
  if(CheckOrderBlock(gapHigh)) confirmations++;
  
  if(confirmations < ConfluenceRequired) return;
  
  // Entry trigger (5M close above gap)
  if(iClose(Symbol(), PERIOD_M5, 0) > gapHigh) {
    double atr = iATR(Symbol(), PERIOD_H1, ATR_Period, 0);
    double sl = gapLow - 1.5 * atr;
    double tp1 = gapHigh + (gapHigh - sl); // 1:1 RR
    double tp2 = iHigh(Symbol(), PERIOD_H4, iHighest(Symbol(), PERIOD_H4, MODE_HIGH, 10, 1));
    
    ExecuteTrade(ORDER_TYPE_BUY, GetPositionSize(), sl, tp1, tp2);
  }
}

void CheckBearishEntry()
{
  double gapHigh, gapLow;
  if(!FindBullishFVG(gapHigh, gapLow)) return;
  
  // Validate FVG age
  if(GetGapAge(gapLow) > MaxGapAge) return;
  
  // Confluence checks
  int confirmations = 0;
  if(CheckVolumeSpike()) confirmations++;
  if(CheckRSIDivergence(false)) confirmations++;
  if(CheckOrderBlock(gapLow)) confirmations++;
  
  if(confirmations < ConfluenceRequired) return;
  
  // Entry trigger (5M close below gap)
  if(iClose(Symbol(), PERIOD_M5, 0) < gapLow) {
    double atr = iATR(Symbol(), PERIOD_H1, ATR_Period, 0);
    double sl = gapHigh + 1.5 * atr;
    double tp1 = gapLow - (sl - gapLow); // 1:1 RR
    double tp2 = iLow(Symbol(), PERIOD_H4, iLowest(Symbol(), PERIOD_H4, MODE_LOW, 10, 1));
    
    ExecuteTrade(ORDER_TYPE_SELL, GetPositionSize(), sl, tp1, tp2);
  }
}

bool FindBearishFVG(double &top, double &bottom)
{
  // Bearish FVG = Three-candle pattern with gap down
  double close2 = iClose(Symbol(), PERIOD_H4, 2);
  double open1 = iOpen(Symbol(), PERIOD_H4, 1);
  
  if(close2 > open1) { // Gap exists
    double low1 = iLow(Symbol(), PERIOD_H4, 1);
    
    // Gap must be significant (at least 5 pips)
    if((close2 - open1) < 5 * Point()) return false;
    
    // Validate gap structure
    if(low1 < iLow(Symbol(), PERIOD_H4, 0) && 
       low1 < iLow(Symbol(), PERIOD_H4, 2)) {
      top = MathMin(close2, open1);
      bottom = low1;
      return true;
    }
  }
  return false;
}

bool FindBullishFVG(double &top, double &bottom)
{
  // Bullish FVG = Three-candle pattern with gap up
  double close2 = iClose(Symbol(), PERIOD_H4, 2);
  double open1 = iOpen(Symbol(), PERIOD_H4, 1);
  
  if(close2 < open1) { // Gap exists
    double high1 = iHigh(Symbol(), PERIOD_H4, 1);
    
    // Gap must be significant (at least 5 pips)
    if((open1 - close2) < 5 * Point()) return false;
    
    // Validate gap structure
    if(high1 > iHigh(Symbol(), PERIOD_H4, 0) && 
       high1 > iHigh(Symbol(), PERIOD_H4, 2)) {
      bottom = MathMax(close2, open1);
      top = high1;
      return true;
    }
  }
  return false;
}

bool CheckVolumeSpike()
{
  double avgVolume = iMA(Symbol(), PERIOD_M15, 20, 0, MODE_SMA, VOLUME_TICK, 0);
  return (iVolume(Symbol(), PERIOD_M15, 0) > 1.5 * avgVolume);
}

bool CheckRSIDivergence(bool bullish)
{
  double rsi0 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 0);
  double rsi1 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 1);
  double rsi2 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 2);
  
  if(bullish) {
    // Bullish divergence: Lower price low, higher RSI low
    return (iLow(Symbol(), PERIOD_H1, 0) < iLow(Symbol(), PERIOD_H1, 1) && 
            rsi0 > rsi1 && rsi1 < rsi2;
  }
  // Bearish divergence: Higher price high, lower RSI high
  return (iHigh(Symbol(), PERIOD_H1, 0) > iHigh(Symbol(), PERIOD_H1, 1) && 
          rsi0 < rsi1 && rsi1 > rsi2;
}

bool CheckOrderBlock(double price)
{
  // Check if near previous daily close
  double prevClose = iClose(Symbol(), PERIOD_D1, 1);
  return (MathAbs(price - prevClose) < 10 * Point());
}
//+------------------------------------------------------------------+
//| Trade Execution & Management                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp1, double tp2)
{
  // Skip if no trading volume
  if(lots <= 0.01) {
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
  request.tp        = tp1; // First take profit
  request.deviation = 5;
  request.comment   = "InverseFVG";
  
  if(OrderSend(request, result)) {
    // Set breakeven trigger
    if(result.order > 0) {
      PendingBreakeven(result.order, request.price);
    }
    
    string log = StringFormat("%s %s %.2f lots | Entry: %.5f | SL: %.5f | TP1: %.5f",
                 (type == ORDER_TYPE_BUY) ? "🟢 BUY" : "🔴 SELL",
                 Symbol(), lots, request.price, sl, tp1);
    SendTelegram(log);
  }
}

void PendingBreakeven(ulong ticket, double entry)
{
  // Place hidden TP to move SL to breakeven
  MqlTradeRequest breakeven = {0};
  MqlTradeResult result = {0};
  
  breakeven.action    = TRADE_ACTION_SLTP;
  breakeven.position  = ticket;
  breakeven.sl        = entry + 5 * Point(); // Slight buffer
  breakeven.tp        = 0; // Keep original TP
  breakeven.symbol    = Symbol();
  
  OrderSend(breakeven, result);
}

void ManageExits()
{
  for(int i=0; i<OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      // Close if gap too old
      if(TimeCurrent() - OrderOpenTime() > MaxGapAge * 3600) {
        OrderClose(OrderTicket(), OrderLots(), 
                  (OrderType()==OP_BUY) ? Bid : Ask, 5);
        SendTelegram("⏱️ Closing Old Trade: " + Symbol());
      }
    }
  }
}
//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
bool IsSymbolAllowed()
{
  for(int i=0; i<3; i++) {
    if(Symbol() == TradePairs[i]) return true;
  }
  return false;
}

int GetGapAge(double gapLevel)
{
  for(int i=1; i<100; i++) {
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
  if(StringLen(TelegramToken) < 10 || ChatID == 0) return;
  
  string headers;
  char   res[], req[];
  string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
  string data = "chat_id=" + (string)ChatID + "&text=" + message;
  
  WebRequest("POST", url, headers, 5000, req, res, headers);
}
//+------------------------------------------------------------------+