//+------------------------------------------------------------------+
//|                                         SMC_Step3_Entry_v2.mq5   |
//|                                      Chuyển đổi từ Pine Script   |
//|                                                                    |
//+------------------------------------------------------------------+
#property copyright "SMC Strategy - Step 3: Trigger Entry Signal (v2)"
#property link      ""
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot buffers
double BuySignalBuffer[];
double SellSignalBuffer[];

//--- Input parameters
input group "═══ CẤU TRÚC THỊ TRƯỜNG ═══"
input int    inp_SwingLength      = 5;           // Swing Length
input bool   inp_ShowSwingHL      = true;        // Hiện Swing High / Low
input bool   inp_ShowBosChoch     = true;        // Hiện BoS / ChoCh
input bool   inp_ShowConfirm      = true;        // Hiện nến xác nhận
input bool   inp_ShowLevels       = true;        // Hiện đường chờ phá vỡ

input group "═══ EMA ═══"
input int    inp_EMALength        = 200;         // EMA Length
input color  inp_EMAColor         = clrGray;     // Màu EMA

input group "═══ TRADE QUALITY ═══"
input bool   inp_ShowFibZone      = true;        // Hiện vùng Discount/Premium
input double inp_FibThreshold     = 50.0;        // Ngưỡng % (Discount/Premium)
input bool   inp_ShowEQ           = true;        // Hiện đường Equilibrium (50%)

input group "═══ ENTRY SIGNAL ═══"
input bool   inp_ShowEntrySignal  = true;        // Hiện tín hiệu Entry
input bool   inp_EnableAlerts     = true;        // Bật Alert

input group "═══ MÀU SẮC ═══"
input color  inp_ColorSH          = clrLimeGreen;    // Swing High
input color  inp_ColorSL          = clrOrange;       // Swing Low (màu cam)
input color  inp_ColorBoS         = clrBlue;         // BoS
input color  inp_ColorChoCh       = clrOrange;       // ChoCh
input color  inp_ColorDiscount    = clrLimeGreen;    // Vùng Discount (Buy)
input color  inp_ColorPremium     = clrRed;          // Vùng Premium (Sell)

//--- Global variables for state tracking
int trend = 0;

double lastSH = 0;
int    lastSHBar = 0;
double prevSH = 0;
int    prevSHBar = 0;

double lastSL = 0;
int    lastSLBar = 0;
double prevSL = 0;
int    prevSLBar = 0;

// Phá vỡ + chờ pullback
bool   waitPullbackUp = false;
double brokenUpLevel = 0;
int    brokenUpBar = 0;
double peakAfterBreakUp = 0;
int    peakAfterBreakUpBar = 0;
bool   isChochUp = false;

bool   waitPullbackDn = false;
double brokenDnLevel = 0;
int    brokenDnBar = 0;
double troughAfterBreakDn = 0;
int    troughAfterBreakDnBar = 0;
bool   isChochDn = false;

// Tracking cực trị
double lowestBetweenSH = 0;
int    lowestBetweenSHBar = 0;
double highestBetweenSL = 0;
int    highestBetweenSLBar = 0;

bool skipAutoSH = false;
bool skipAutoSL = false;

// Trade Quality
double swingHigh_fib = 0;
double swingLow_fib = 0;
int    fibStartBar = 0;

double eq50 = 0;
double discountLevel = 0;
double premiumLevel = 0;

bool inDiscountZone = false;
bool inPremiumZone = false;

// Entry Signal tracking
bool hasEnteredDiscount = false;
bool hasEnteredPremium = false;

bool setupBuyValid = true;
bool setupSellValid = true;

bool newSwingConfirmed = false;

bool checkedFirstBuy = false;
bool checkedFirstSell = false;

int buyTriggerCount = 0;
int sellTriggerCount = 0;

double predictedLow = 0;
double predictedHigh = 0;

double currentLowInDiscount = 0;
double currentHighInPremium = 0;

// EMA handle
int ema_handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellSignalBuffer, INDICATOR_DATA);
   
   //--- Set plot properties - TẮT hiển thị để tránh trùng
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);  // Tắt vẽ
   PlotIndexSetString(0, PLOT_LABEL, "Buy Signal");
   
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);  // Tắt vẽ
   PlotIndexSetString(1, PLOT_LABEL, "Sell Signal");
   
   //--- Initialize EMA
   ema_handle = iMA(_Symbol, _Period, inp_EMALength, 0, MODE_EMA, PRICE_CLOSE);
   if(ema_handle == INVALID_HANDLE)
   {
      Print("Lỗi khởi tạo EMA");
      return(INIT_FAILED);
   }
   
   //--- Set indicator short name
   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Step 3 Entry v2");
   
   //--- Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release EMA handle
   if(ema_handle != INVALID_HANDLE)
      IndicatorRelease(ema_handle);
   
   //--- Remove all objects
   ObjectsDeleteAll(0, "SMC_");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   
   //--- Get EMA values
   double ema200[];
   ArraySetAsSeries(ema200, true);
   if(CopyBuffer(ema_handle, 0, 0, rates_total, ema200) <= 0)
      return(0);
   
   //--- Main calculation loop
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   
   for(int i = limit - 1; i >= 0; i--)
   {
      //--- Initialize buffers
      BuySignalBuffer[i] = 0;
      SellSignalBuffer[i] = 0;
      
      //--- Check confirmation candles
      bool isConfirmHigh = (i < rates_total - 1) ? (close[i] < low[i+1]) : false;
      bool isConfirmLow = (i < rates_total - 1) ? (close[i] > high[i+1]) : false;
      
      //--- Track extremes
      if(trend >= 0)
      {
         if(lowestBetweenSH == 0 || low[i] < lowestBetweenSH)
         {
            lowestBetweenSH = low[i];
            lowestBetweenSHBar = i;
         }
      }
      
      if(trend <= 0)
      {
         if(highestBetweenSL == 0 || high[i] > highestBetweenSL)
         {
            highestBetweenSL = high[i];
            highestBetweenSLBar = i;
         }
      }
      
      //--- UPTREND LOGIC
      if(trend >= 0)
      {
         // Check breakout above lastSH
         if(!waitPullbackUp && lastSH > 0)
         {
            if(close[i] > lastSH)
            {
               waitPullbackUp = true;
               brokenUpLevel = lastSH;
               brokenUpBar = lastSHBar;
               peakAfterBreakUp = high[i];
               peakAfterBreakUpBar = i;
               isChochUp = false;
            }
         }
         
         // Wait for pullback confirmation
         if(waitPullbackUp)
         {
            if(high[i] > peakAfterBreakUp)
            {
               peakAfterBreakUp = high[i];
               peakAfterBreakUpBar = i;
            }
            
            if(isConfirmHigh)
            {
               waitPullbackUp = false;
               
               // Update swing highs
               prevSH = lastSH;
               prevSHBar = lastSHBar;
               lastSH = peakAfterBreakUp;
               lastSHBar = peakAfterBreakUpBar;
               
               // Auto update swing low
               if(!skipAutoSL)
               {
                  prevSL = lastSL;
                  prevSLBar = lastSLBar;
                  lastSL = lowestBetweenSH;
                  lastSLBar = lowestBetweenSHBar;
                  
                  // Draw SL label
                  if(inp_ShowSwingHL)
                     DrawSwingLabel("SL", time[lastSLBar], lastSL, true, inp_ColorSL);
               }
               else
               {
                  skipAutoSL = false;
               }
               
               // Draw SH label
               if(inp_ShowSwingHL)
                  DrawSwingLabel("SH", time[lastSHBar], lastSH, false, inp_ColorSH);
               
               if(inp_ShowConfirm)
                  DrawConfirmLabel(time[i], high[i], false, inp_ColorSH);
               
               trend = 1;
               
               // Update Fib levels
               UpdateFibLevels();
               
               // Reset entry tracking
               ResetBuyTracking();
               newSwingConfirmed = true;
               
               lowestBetweenSH = low[i];
               lowestBetweenSHBar = i;
            }
         }
         
         // Check for ChoCh down
         if(!waitPullbackDn && lastSL > 0 && trend == 1)
         {
            if(close[i] < lastSL)
            {
               waitPullbackDn = true;
               brokenDnLevel = lastSL;
               brokenDnBar = lastSLBar;
               troughAfterBreakDn = low[i];
               troughAfterBreakDnBar = i;
               isChochDn = true;
               skipAutoSH = true;
               
               waitPullbackUp = false;
               trend = -1;
               
               newSwingConfirmed = false;
               ResetSellTracking();
               ResetBuyTracking();
               
               highestBetweenSL = high[i];
               highestBetweenSLBar = i;
            }
         }
      }
      
      //--- DOWNTREND LOGIC
      if(trend == -1)
      {
         // Check breakout below lastSL
         if(!waitPullbackDn && lastSL > 0)
         {
            if(close[i] < lastSL)
            {
               waitPullbackDn = true;
               brokenDnLevel = lastSL;
               brokenDnBar = lastSLBar;
               troughAfterBreakDn = low[i];
               troughAfterBreakDnBar = i;
               isChochDn = false;
            }
         }
         
         // Wait for pullback confirmation
         if(waitPullbackDn)
         {
            if(low[i] < troughAfterBreakDn)
            {
               troughAfterBreakDn = low[i];
               troughAfterBreakDnBar = i;
            }
            
            if(isConfirmLow)
            {
               waitPullbackDn = false;
               
               // Update swing lows
               prevSL = lastSL;
               prevSLBar = lastSLBar;
               lastSL = troughAfterBreakDn;
               lastSLBar = troughAfterBreakDnBar;
               
               // Auto update swing high
               if(!skipAutoSH)
               {
                  prevSH = lastSH;
                  prevSHBar = lastSHBar;
                  lastSH = highestBetweenSL;
                  lastSHBar = highestBetweenSLBar;
                  
                  // Draw SH label
                  if(inp_ShowSwingHL)
                     DrawSwingLabel("SH", time[lastSHBar], lastSH, false, inp_ColorSH);
               }
               else
               {
                  skipAutoSH = false;
               }
               
               // Draw SL label
               if(inp_ShowSwingHL)
                  DrawSwingLabel("SL", time[lastSLBar], lastSL, true, inp_ColorSL);
               
               if(inp_ShowConfirm)
                  DrawConfirmLabel(time[i], low[i], true, inp_ColorSL);
               
               trend = -1;
               
               // Update Fib levels
               UpdateFibLevels();
               
               // Reset entry tracking
               ResetSellTracking();
               newSwingConfirmed = true;
               
               highestBetweenSL = high[i];
               highestBetweenSLBar = i;
            }
         }
         
         // Check for ChoCh up
         if(!waitPullbackUp && lastSH > 0 && trend == -1)
         {
            if(close[i] > lastSH)
            {
               waitPullbackUp = true;
               brokenUpLevel = lastSH;
               brokenUpBar = lastSHBar;
               peakAfterBreakUp = high[i];
               peakAfterBreakUpBar = i;
               isChochUp = true;
               skipAutoSL = true;
               
               waitPullbackDn = false;
               trend = 1;
               
               newSwingConfirmed = false;
               ResetBuyTracking();
               ResetSellTracking();
               
               lowestBetweenSH = low[i];
               lowestBetweenSHBar = i;
            }
         }
      }
      
      //--- INITIALIZATION
      if(trend == 0)
      {
         double pivotH = FindPivotHigh(high, i, inp_SwingLength);
         double pivotL = FindPivotLow(low, i, inp_SwingLength);
         
         if(pivotH > 0)
         {
            if(lastSH == 0 || pivotH > lastSH)
            {
               prevSH = lastSH;
               prevSHBar = lastSHBar;
               lastSH = pivotH;
               lastSHBar = i;
               
               // Draw SH label immediately
               if(inp_ShowSwingHL)
                  DrawSwingLabel("SH_Init", time[i], lastSH, false, clrGray);
            }
         }
         
         if(pivotL > 0)
         {
            if(lastSL == 0 || pivotL < lastSL)
            {
               prevSL = lastSL;
               prevSLBar = lastSLBar;
               lastSL = pivotL;
               lastSLBar = i;
               
               // Draw SL label immediately
               if(inp_ShowSwingHL)
                  DrawSwingLabel("SL_Init", time[i], lastSL, true, clrGray);
            }
         }
         
         if(lastSH > 0 && lastSL > 0)
         {
            if(prevSH > 0 && lastSH > prevSH)
            {
               trend = 1;
               lowestBetweenSH = low[i];
               lowestBetweenSHBar = i;
            }
            else if(prevSL > 0 && lastSL < prevSL)
            {
               trend = -1;
               highestBetweenSL = high[i];
               highestBetweenSLBar = i;
            }
         }
      }
      
      //--- Track entry into zones
      if(trend == 1 && discountLevel > 0)
      {
         inDiscountZone = (low[i] <= discountLevel);
         inPremiumZone = false;
         
         if(inDiscountZone && !hasEnteredDiscount)
         {
            hasEnteredDiscount = true;
            currentLowInDiscount = low[i];
         }
         
         if(inDiscountZone && !checkedFirstBuy)
         {
            if(currentLowInDiscount == 0 || low[i] < currentLowInDiscount)
               currentLowInDiscount = low[i];
         }
      }
      else if(trend == -1 && premiumLevel > 0)
      {
         inPremiumZone = (high[i] >= premiumLevel);
         inDiscountZone = false;
         
         if(inPremiumZone && !hasEnteredPremium)
         {
            hasEnteredPremium = true;
            currentHighInPremium = high[i];
         }
         
         if(inPremiumZone && !checkedFirstSell)
         {
            if(currentHighInPremium == 0 || high[i] > currentHighInPremium)
               currentHighInPremium = high[i];
         }
      }
      
      //--- BUY SIGNAL LOGIC
      if(trend == 1 && newSwingConfirmed && setupBuyValid && hasEnteredDiscount)
      {
         if(!checkedFirstBuy && isConfirmLow)
         {
            checkedFirstBuy = true;
            predictedLow = currentLowInDiscount;
            
            if(close[i] > ema200[i])
            {
               BuySignalBuffer[i] = low[i];
               buyTriggerCount = 1;
               
               // Draw BUY signal
               DrawBuySignal(time[i], low[i], "BUY #1");
               
               if(inp_EnableAlerts && i == 0)
                  Alert("🟢 BUY #1 | Price: ", DoubleToString(close[i], _Digits), " | EMA200: ", DoubleToString(ema200[i], _Digits));
            }
            else
            {
               setupBuyValid = false;
            }
         }
         else if(buyTriggerCount == 1 && isConfirmLow)
         {
            if(predictedLow > 0 && low[i] < predictedLow && close[i] > ema200[i])
            {
               BuySignalBuffer[i] = low[i];
               buyTriggerCount = 2;
               
               // Draw BUY signal #2
               DrawBuySignal(time[i], low[i], "BUY #2");
               
               if(inp_EnableAlerts && i == 0)
                  Alert("🟢 BUY #2 (Sweep) | Price: ", DoubleToString(close[i], _Digits), " | Swept: ", DoubleToString(predictedLow, _Digits));
            }
         }
      }
      
      //--- SELL SIGNAL LOGIC
      if(trend == -1 && newSwingConfirmed && setupSellValid && hasEnteredPremium)
      {
         if(!checkedFirstSell && isConfirmHigh)
         {
            checkedFirstSell = true;
            predictedHigh = currentHighInPremium;
            
            if(close[i] < ema200[i])
            {
               SellSignalBuffer[i] = high[i];
               sellTriggerCount = 1;
               
               // Draw SELL signal
               DrawSellSignal(time[i], high[i], "SELL #1");
               
               if(inp_EnableAlerts && i == 0)
                  Alert("🔴 SELL #1 | Price: ", DoubleToString(close[i], _Digits), " | EMA200: ", DoubleToString(ema200[i], _Digits));
            }
            else
            {
               setupSellValid = false;
            }
         }
         else if(sellTriggerCount == 1 && isConfirmHigh)
         {
            if(predictedHigh > 0 && high[i] > predictedHigh && close[i] < ema200[i])
            {
               SellSignalBuffer[i] = high[i];
               sellTriggerCount = 2;
               
               // Draw SELL signal #2
               DrawSellSignal(time[i], high[i], "SELL #2");
               
               if(inp_EnableAlerts && i == 0)
                  Alert("🔴 SELL #2 (Sweep) | Price: ", DoubleToString(close[i], _Digits), " | Swept: ", DoubleToString(predictedHigh, _Digits));
            }
         }
      }
   }
   
   //--- Draw visual elements on last bar
   if(prev_calculated == 0 || rates_total - prev_calculated > 1)
   {
      DrawFibZone();
      DrawLevels();
   }
   
   //--- Return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Find Pivot High                                                  |
//+------------------------------------------------------------------+
double FindPivotHigh(const double &high[], int index, int length)
{
   if(index < length || index >= ArraySize(high) - length)
      return 0;
   
   double center = high[index];
   
   for(int i = 1; i <= length; i++)
   {
      if(high[index - i] >= center || high[index + i] >= center)
         return 0;
   }
   
   return center;
}

//+------------------------------------------------------------------+
//| Find Pivot Low                                                   |
//+------------------------------------------------------------------+
double FindPivotLow(const double &low[], int index, int length)
{
   if(index < length || index >= ArraySize(low) - length)
      return 0;
   
   double center = low[index];
   
   for(int i = 1; i <= length; i++)
   {
      if(low[index - i] <= center || low[index + i] <= center)
         return 0;
   }
   
   return center;
}

//+------------------------------------------------------------------+
//| Update Fibonacci Levels                                          |
//+------------------------------------------------------------------+
void UpdateFibLevels()
{
   swingHigh_fib = lastSH;
   swingLow_fib = lastSL;
   fibStartBar = 0; // Will be updated with actual bar
   
   double swingRange = swingHigh_fib - swingLow_fib;
   eq50 = swingLow_fib + (swingRange * 0.5);
   
   if(trend == 1)
   {
      discountLevel = swingLow_fib + (swingRange * (inp_FibThreshold / 100.0));
      premiumLevel = 0;
   }
   else if(trend == -1)
   {
      premiumLevel = swingHigh_fib - (swingRange * (inp_FibThreshold / 100.0));
      discountLevel = 0;
   }
}

//+------------------------------------------------------------------+
//| Reset Buy Tracking                                               |
//+------------------------------------------------------------------+
void ResetBuyTracking()
{
   hasEnteredDiscount = false;
   setupBuyValid = true;
   checkedFirstBuy = false;
   buyTriggerCount = 0;
   predictedLow = 0;
   currentLowInDiscount = 0;
}

//+------------------------------------------------------------------+
//| Reset Sell Tracking                                              |
//+------------------------------------------------------------------+
void ResetSellTracking()
{
   hasEnteredPremium = false;
   setupSellValid = true;
   checkedFirstSell = false;
   sellTriggerCount = 0;
   predictedHigh = 0;
   currentHighInPremium = 0;
}

//+------------------------------------------------------------------+
//| Helper function to create color from RGB                         |
//+------------------------------------------------------------------+
color clrColor(int r, int g, int b)
{
   return (color)((b << 16) | (g << 8) | r);
}

//+------------------------------------------------------------------+
//| Draw Buy Signal                                                  |
//+------------------------------------------------------------------+
void DrawBuySignal(datetime barTime, double price, string label)
{
   if(!inp_ShowEntrySignal) return;
   
   // Tạo tên unique với cả label
   string uniqueID = TimeToString(barTime) + "_" + label;
   string objName = "SMC_BuySignal_" + uniqueID;
   
   // Delete old if exists
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   
   // Create arrow - width = 1, màu xanh ngọc (38,166,154)
   color buyColor = clrColor(38, 166, 154);
   ObjectCreate(0, objName, OBJ_ARROW, 0, barTime, price);
   ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 233); // Up arrow
   ObjectSetInteger(0, objName, OBJPROP_COLOR, buyColor);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   
   // Create label - dưới mũi tên, tính offset theo % của visible range
   string labelName = "SMC_BuyLabel_" + uniqueID;
   if(ObjectFind(0, labelName) >= 0)
      ObjectDelete(0, labelName);
   
   // Tính khoảng cách dựa trên visible chart range - tăng lên 4%
   double chartHigh = ChartGetDouble(0, CHART_PRICE_MAX);
   double chartLow = ChartGetDouble(0, CHART_PRICE_MIN);
   double chartRange = chartHigh - chartLow;
   double offset = -chartRange * 0.04; // 4% của visible range (tăng từ 2%)
   
   ObjectCreate(0, labelName, OBJ_TEXT, 0, barTime, price + offset);
   ObjectSetString(0, labelName, OBJPROP_TEXT, label);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, buyColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_UPPER); // Căn giữa ngang
   ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Sell Signal                                                 |
//+------------------------------------------------------------------+
void DrawSellSignal(datetime barTime, double price, string label)
{
   if(!inp_ShowEntrySignal) return;
   
   // Tạo tên unique với cả label
   string uniqueID = TimeToString(barTime) + "_" + label;
   string objName = "SMC_SellSignal_" + uniqueID;
   
   // Delete old if exists
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   
   // Create arrow - đặt cao hơn để không đè lên nến
   color sellColor = clrColor(239, 83, 80);
   
   // Tính offset cho icon - cao hơn price
   double chartHigh = ChartGetDouble(0, CHART_PRICE_MAX);
   double chartLow = ChartGetDouble(0, CHART_PRICE_MIN);
   double chartRange = chartHigh - chartLow;
   double arrowOffset = chartRange * 0.015; // Icon cách nến 1.5%
   
   ObjectCreate(0, objName, OBJ_ARROW, 0, barTime, price + arrowOffset);
   ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 234); // Down arrow
   ObjectSetInteger(0, objName, OBJPROP_COLOR, sellColor);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   
   // Create label - trên icon, tính offset theo % của visible range
   string labelName = "SMC_SellLabel_" + uniqueID;
   if(ObjectFind(0, labelName) >= 0)
      ObjectDelete(0, labelName);
   
   // Label cao hơn icon thêm 4%
   double offset = chartRange * 0.04; // 4% của visible range
   
   ObjectCreate(0, labelName, OBJ_TEXT, 0, barTime, price + arrowOffset + offset);
   ObjectSetString(0, labelName, OBJPROP_TEXT, label);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, sellColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LOWER); // Căn giữa ngang
   ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Swing Label                                                 |
//+------------------------------------------------------------------+
void DrawSwingLabel(string label, datetime barTime, double price, bool isLow, color clr)
{
   if(!inp_ShowSwingHL) return;
   
   string objName = "SMC_Swing_" + label + "_" + TimeToString(barTime);
   
   // Delete old label if exists
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   
   // Create text label
   ObjectCreate(0, objName, OBJ_TEXT, 0, barTime, price);
   ObjectSetString(0, objName, OBJPROP_TEXT, label);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, objName, OBJPROP_FONT, "Arial Bold");
   // ANCHOR_UPPER = căn giữa ngang, label ở trên điểm
   // ANCHOR_LOWER = căn giữa ngang, label ở dưới điểm
   if(isLow)
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_UPPER);  // SL ở trên đáy
   else
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LOWER);  // SH ở dưới đỉnh
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Confirmation Label                                          |
//+------------------------------------------------------------------+
void DrawConfirmLabel(datetime barTime, double price, bool isLow, color clr)
{
   string objName = "SMC_Confirm_" + TimeToString(barTime);
   
   // Delete old label if exists
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   
   // Create text label
   ObjectCreate(0, objName, OBJ_TEXT, 0, barTime, price);
   ObjectSetString(0, objName, OBJPROP_TEXT, "✓");
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isLow ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Zone                                              |
//+------------------------------------------------------------------+
void DrawFibZone()
{
   if(!inp_ShowFibZone || swingHigh_fib == 0 || swingLow_fib == 0)
      return;
   
   // Remove old zone
   ObjectDelete(0, "SMC_FibZone");
   
   datetime time2 = TimeCurrent() + PeriodSeconds(_Period) * 10;
   
   if(trend == 1 && discountLevel > 0)
   {
      // Draw Discount zone - từ nến SH (lastSHBar)
      datetime time1 = iTime(_Symbol, _Period, lastSHBar);
      color discountColor = clrColor(63, 63, 63);
      ObjectCreate(0, "SMC_FibZone", OBJ_RECTANGLE, 0, time1, discountLevel, time2, swingLow_fib);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_COLOR, discountColor);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_FILL, true);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_BACK, true);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_WIDTH, 1);
   }
   else if(trend == -1 && premiumLevel > 0)
   {
      // Draw Premium zone - từ nến SL (lastSLBar)
      datetime time1 = iTime(_Symbol, _Period, lastSLBar);
      ObjectCreate(0, "SMC_FibZone", OBJ_RECTANGLE, 0, time1, swingHigh_fib, time2, premiumLevel);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_COLOR, inp_ColorPremium);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_FILL, true);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_BACK, true);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "SMC_FibZone", OBJPROP_WIDTH, 1);
   }
   
   // Draw EQ line
   if(inp_ShowEQ && eq50 > 0)
   {
      ObjectDelete(0, "SMC_EQ50");
      ObjectCreate(0, "SMC_EQ50", OBJ_HLINE, 0, 0, eq50);
      ObjectSetInteger(0, "SMC_EQ50", OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "SMC_EQ50", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SMC_EQ50", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "SMC_EQ50", OBJPROP_SELECTABLE, false);
      ObjectSetString(0, "SMC_EQ50", OBJPROP_TEXT, "EQ 50%");
   }
}

//+------------------------------------------------------------------+
//| Draw Levels                                                      |
//+------------------------------------------------------------------+
void DrawLevels()
{
   if(!inp_ShowLevels)
      return;
   
   ObjectDelete(0, "SMC_LevelHigh");
   ObjectDelete(0, "SMC_LevelLow");
   
   if(lastSH > 0)
   {
      ObjectCreate(0, "SMC_LevelHigh", OBJ_HLINE, 0, 0, lastSH);
      ObjectSetInteger(0, "SMC_LevelHigh", OBJPROP_COLOR, inp_ColorSH);
      ObjectSetInteger(0, "SMC_LevelHigh", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SMC_LevelHigh", OBJPROP_WIDTH, 1);
      ObjectSetString(0, "SMC_LevelHigh", OBJPROP_TEXT, "Last SH");
   }
   
   if(lastSL > 0)
   {
      ObjectCreate(0, "SMC_LevelLow", OBJ_HLINE, 0, 0, lastSL);
      ObjectSetInteger(0, "SMC_LevelLow", OBJPROP_COLOR, inp_ColorSL);
      ObjectSetInteger(0, "SMC_LevelLow", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SMC_LevelLow", OBJPROP_WIDTH, 1);
      ObjectSetString(0, "SMC_LevelLow", OBJPROP_TEXT, "Last SL");
   }
}
//+------------------------------------------------------------------+