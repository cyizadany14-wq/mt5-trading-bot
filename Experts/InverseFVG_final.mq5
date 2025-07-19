//+------------------------------------------------------------------+
//|                                  InverseFVG_Trend_Strategy.mq5   |
//|               Inverse FVG with Trend-Following Strategy (v2.0)   |
//|                        Copyright 2025, Smartphone_FVG_Bot        |
//|                                    https://www.example.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Smartphone_FVG_Bot"
#property link      "https://www.example.com"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <newsfilter.mqh>
#include <MovingAverages.mqh>

//--- Input Parameters
input double   RiskPercent = 1.0;        // Risk per trade (% of balance)
input int      ATR_Period = 14;           // ATR period for SL calculation
input int      RSI_Period = 14;           // RSI period for divergence
input int      ADX_Threshold = 25;        // Min ADX for trending markets
input bool     EnableNewsFilter = true;   // Enable news filter
input ENUM_TIMEFRAMES HTF_Trend = PERIOD_H4; // Higher timeframe for trend
input ENUM_TIMEFRAMES LTF_Entry = PERIOD_M5; // Lower timeframe for entries

//--- Global Variables
CTrade trade;
int magicNumber = 20250719;
string allowedPairs[] = {"EURUSD", "USDJPY", "GBPUSD"};

// FVG Structure
struct FVGZone {
   datetime timestamp;
   double top;
   double bottom;
   int type;          // 1 = Bearish FVG, -1 = Bullish FVG
   bool triggered;
};
FVGZone fvgZones[10];
int fvgCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   ArraySetAsSeries(fvgZones, true);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Only process on new bar
   static datetime lastBarTime;
   datetime currentBarTime = iTime(_Symbol, LTF_Entry, 0);
   if(lastBarTime == currentBarTime) return;
   lastBarTime = currentBarTime;
   
   // Check pair permission
   if(!IsPairAllowed()) return;
   
   // Check news filter
   if(EnableNewsFilter && !NewsFilter::IsSafeToTrade()) {
      Comment("News Filter Active - Trading Paused");
      return;
   }
   
   // Check market conditions
   if(iADX(_Symbol, HTF_Trend, 14, PRICE_CLOSE, MODE_MAIN, 0) < ADX_Threshold) {
      Comment("Sideways Market (ADX < ", ADX_Threshold, ")");
      return;
   }
   
   // Update FVG zones (scan higher timeframe)
   ScanForFVGs(HTF_Trend);
   
   // Check for entry signals
   CheckEntryConditions();
}

//+------------------------------------------------------------------+
//| Scan for FVGs on specified timeframe                             |
//+------------------------------------------------------------------+
void ScanForFVGs(ENUM_TIMEFRAMES tf) {
   // Clear old FVGs (>3 days)
   for(int i = fvgCount-1; i >= 0; i--) {
      if(TimeCurrent() - fvgZones[i].timestamp > 3*86400) {
         RemoveFVG(i);
      }
   }
   
   // Scan for new FVGs (simplified logic)
   for(int i = 3; i <= 50; i++) {
      double high1 = iHigh(_Symbol, tf, i);
      double low1 = iLow(_Symbol, tf, i);
      double high0 = iHigh(_Symbol, tf, i-1);
      double low0 = iLow(_Symbol, tf, i-1);
      
      // Bearish FVG (supply zone)
      if(low0 > high1) {
         AddFVG(iTime(_Symbol, tf, i), high1, low0, 1);
      }
      // Bullish FVG (demand zone)
      else if(high0 < low1) {
         AddFVG(iTime(_Symbol, tf, i), low1, high0, -1);
      }
   }
}

//+------------------------------------------------------------------+
//| Add new FVG zone                                                 |
//+------------------------------------------------------------------+
void AddFVG(datetime time, double top, double bottom, int type) {
   // Check if already exists
   for(int i = 0; i < fvgCount; i++) {
      if(MathAbs(fvgZones[i].top - top) < 10*_Point && 
         MathAbs(fvgZones[i].bottom - bottom) < 10*_Point) {
         return;
      }
   }
   
   // Add new zone
   if(fvgCount < 10) {
      fvgZones[fvgCount].timestamp = time;
      fvgZones[fvgCount].top = top;
      fvgZones[fvgCount].bottom = bottom;
      fvgZones[fvgCount].type = type;
      fvgZones[fvgCount].triggered = false;
      fvgCount++;
   }
}

//+------------------------------------------------------------------+
//| Check FVG entry conditions                                       |
//+------------------------------------------------------------------+
void CheckEntryConditions() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = iATR(_Symbol, LTF_Entry, ATR_Period, 0);
   double volumeArray[];
   CopyTickVolume(_Symbol, LTF_Entry, 0, 20, volumeArray);
   double avgVolume = SimpleMA(19, 0, volumeArray);
   
   for(int i = 0; i < fvgCount; i++) {
      if(fvgZones[i].triggered) continue;
      
      // Bullish Setup (Uptrend with Bearish FVG)
      if(IsUptrend() && fvgZones[i].type == 1 && 
         currentPrice > fvgZones[i].bottom && currentPrice < fvgZones[i].top) {
         
         // Entry condition: 5M close above FVG top
         if(iClose(_Symbol, LTF_Entry, 1) > fvgZones[i].top) {
            // Volume confirmation
            if(iVolume(_Symbol, LTF_Entry, 0) > 1.5 * avgVolume) {
               ExecuteBuy(fvgZones[i].bottom, atr);
               fvgZones[i].triggered = true;
            }
         }
      }
      
      // Bearish Setup (Downtrend with Bullish FVG)
      if(IsDowntrend() && fvgZones[i].type == -1 && 
         currentPrice > fvgZones[i].bottom && currentPrice < fvgZones[i].top) {
         
         // Entry condition: 5M close below FVG bottom
         if(iClose(_Symbol, LTF_Entry, 1) < fvgZones[i].bottom) {
            // RSI rejection confirmation
            double rsi = iRSI(_Symbol, LTF_Entry, RSI_Period, PRICE_CLOSE, 0);
            if(rsi > 60 && rsi < 65 && iRSI(_Symbol, LTF_Entry, RSI_Period, PRICE_CLOSE, 1) > rsi) {
               ExecuteSell(fvgZones[i].top, atr);
               fvgZones[i].triggered = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuy(double fvgBottom, double atr) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100;
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calculate SL (1.5x ATR below gap low)
   double sl = fvgBottom - 1.5 * atr;
   double slPoints = (ask - sl) / _Point;
   double lotSize = NormalizeDouble(riskAmount / (slPoints * pointValue), 2);
   
   // Validate lot size
   lotSize = fmin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   lotSize = fmax(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   
   // Calculate TP levels
   double tp1 = ask + (ask - sl); // 1:1 RR
   double tp2 = ask + 2*(ask - sl); // 1:2 RR
   
   // Place order
   if(trade.Buy(lotSize, _Symbol, ask, sl, 0, "Inverse FVG Buy")) {
      // Set TP levels
      ulong ticket = trade.ResultOrder();
      trade.OrderModify(ticket, sl, tp1, 0, 0);
      
      // Add breakeven logic in OnTrade()
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                               |
//+------------------------------------------------------------------+
void ExecuteSell(double fvgTop, double atr) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100;
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calculate SL (1.5x ATR above gap high)
   double sl = fvgTop + 1.5 * atr;
   double slPoints = (sl - bid) / _Point;
   double lotSize = NormalizeDouble(riskAmount / (slPoints * pointValue), 2);
   
   // Validate lot size
   lotSize = fmin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   lotSize = fmax(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   
   // Calculate TP levels
   double tp1 = bid - (sl - bid); // 1:1 RR
   double tp2 = bid - 2*(sl - bid); // 1:2 RR
   
   // Place order
   if(trade.Sell(lotSize, _Symbol, bid, sl, 0, "Inverse FVG Sell")) {
      // Set TP levels
      ulong ticket = trade.ResultOrder();
      trade.OrderModify(ticket, sl, tp1, 0, 0);
   }
}

//+------------------------------------------------------------------+
//| Trend Detection Functions                                        |
//+------------------------------------------------------------------+
bool IsUptrend() {
   // Higher Highs/Higher Lows structure
   if(iHigh(_Symbol, HTF_Trend, 1) > iHigh(_Symbol, HTF_Trend, 2) &&
      iLow(_Symbol, HTF_Trend, 1) > iLow(_Symbol, HTF_Trend, 2)) {
      // Price above 200 EMA
      if(iClose(_Symbol, HTF_Trend, 0) > iMA(_Symbol, HTF_Trend, 200, 0, MODE_EMA, PRICE_CLOSE, 0)) {
         return true;
      }
   }
   return false;
}

bool IsDowntrend() {
   // Lower Highs/Lower Lows structure
   if(iHigh(_Symbol, HTF_Trend, 1) < iHigh(_Symbol, HTF_Trend, 2) &&
      iLow(_Symbol, HTF_Trend, 1) < iLow(_Symbol, HTF_Trend, 2)) {
      // Price below 200 EMA
      if(iClose(_Symbol, HTF_Trend, 0) < iMA(_Symbol, HTF_Trend, 200, 0, MODE_EMA, PRICE_CLOSE, 0)) {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trade function (for breakeven triggers)                          |
//+------------------------------------------------------------------+
void OnTrade() {
   // Move SL to breakeven when TP1 hit
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == magicNumber) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         
         // Check if TP1 hit (first profit target)
         if(tp > 0 && PositionGetDouble(POSITION_PRICE_CURRENT) >= tp) {
            // Move SL to entry price
            trade.PositionModify(ticket, openPrice, 0);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
bool IsPairAllowed() {
   string currentSymbol = _Symbol;
   for(int i = 0; i < ArraySize(allowedPairs); i++) {
      if(currentSymbol == allowedPairs[i]) {
         return true;
      }
   }
   return false;
}

void RemoveFVG(int index) {
   for(int i = index; i < fvgCount-1; i++) {
      fvgZones[i] = fvgZones[i+1];
   }
   fvgCount--;
}

double SimpleMA(int period, int shift, double &array[]) {
   double sum = 0;
   for(int i = 0; i < period; i++) {
      sum += array[shift+i];
   }
   return sum/period;
}