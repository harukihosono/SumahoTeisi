//+------------------------------------------------------------------+
//|                                                  SumahoTeisi.mq4 |
//|                                         Copyright 2025, HosonoP |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HosonoP"
#property version   "1.00"
#property strict

#include <WinUser32.mqh>
#include "SumahoTeisi_Common.mqh"

//+------------------------------------------------------------------+
//| DLLインポート                                                     |
//+------------------------------------------------------------------+
#import "user32.dll"
int GetAncestor(int hWnd, int flags);
int PostMessageA(int hWnd, int Msg, int wParam, int lParam);
#import

//+------------------------------------------------------------------+
//| 自動売買の状態を切り替える（MT4版）                               |
//+------------------------------------------------------------------+
void ToggleAutoTrading(bool enable)
{
   int main = GetAncestor(WindowHandle(Symbol(), Period()), GA_ROOT);
   bool currentState = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   if(enable != currentState)
   {
      PostMessageA(main, WM_COMMAND, 33020, 0);
   }

   g_autoTradingEnabled = enable;
   LogMessage("Auto Trading: " + (enable ? "ON" : "OFF"));
}

//+------------------------------------------------------------------+
//| 手動切り替え関数                                                  |
//+------------------------------------------------------------------+
void ManualToggle()
{
   if(s_canToggle && !g_eaStopped)
   {
      bool newState = !g_autoTradingEnabled;
      ToggleAutoTrading(newState);
      s_lastManualState = newState;
   }
}

//+------------------------------------------------------------------+
//| 全ポジション・オーダー決済（MT4版）                               |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders()
{
   bool orderClosed;

   // ポジションを決済
   do
   {
      orderClosed = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
            {
               double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
               if(OrderClose(OrderTicket(), OrderLots(), closePrice, 3))
               {
                  orderClosed = true;
                  LogMessage("Position closed: Ticket=" + IntegerToString(OrderTicket()));
               }
            }
         }
      }
   }
   while(orderClosed);

   // 待機注文を削除
   do
   {
      orderClosed = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT ||
               OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
            {
               if(OrderDelete(OrderTicket()))
               {
                  orderClosed = true;
                  LogMessage("Order deleted: Ticket=" + IntegerToString(OrderTicket()));
               }
            }
         }
      }
   }
   while(orderClosed);
}

//+------------------------------------------------------------------+
//| 価格制限による全決済＆EA停止処理                                  |
//+------------------------------------------------------------------+
void ProcessPriceLimitStop(int limitType)
{
   string reason = (limitType == 1) ? "上限価格超過" : "下限価格割れ";
   double limitPrice = (limitType == 1) ? InpUpperPriceLimit : InpLowerPriceLimit;

   string subject = "【SumahoTeisi】" + reason;
   string message = "【警告】" + reason + "を検出！ Price=" + DoubleToString(Close[0], Digits) +
                    " Limit=" + DoubleToString(limitPrice, Digits) + " 全決済してEAを停止します。";

   // 全通知送信（アラート、スマホ、メール）
   SendAllNotifications(subject, message);

   // 全ポジション・オーダー決済
   CloseAllPositionsAndOrders();

   // EA停止フラグをセット
   g_eaStopped = true;
   s_priceLimitTriggered = true;

   // 自動売買をOFF
   ToggleAutoTrading(false);

   // EAを削除（完全停止）
   LogMessage("EA停止処理完了。EAをチャートから削除します。");
   ExpertRemove();
}

//+------------------------------------------------------------------+
//| 初期化関数                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   LogMessage("EA initialized");
   LogMessage("Upper Price Limit: " + (InpUpperPriceLimit > 0 ? DoubleToString(InpUpperPriceLimit, Digits) : "Disabled"));
   LogMessage("Lower Price Limit: " + (InpLowerPriceLimit > 0 ? DoubleToString(InpLowerPriceLimit, Digits) : "Disabled"));

   g_eaStopped = false;
   s_priceLimitTriggered = false;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 終了処理                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogMessage("EA deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| ティック関数                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // EA停止中は何もしない
   if(g_eaStopped)
      return;

   // 価格制限チェック（現在価格）
   double currentPrice = Close[0];
   int limitCheck = CheckPriceLimit(currentPrice);

   if(limitCheck != 0)
   {
      ProcessPriceLimitStop(limitCheck);
      return;
   }

   // 既存のロジック
   bool A = false, B = false;
   bool orderExists = false;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         A = StringFind(OrderSymbol(), "USDJPY") != -1 &&
             OrderType() == OP_SELLLIMIT &&
             OrderOpenPrice() == 200.0;
         B = StringFind(OrderSymbol(), "BTCUSD") != -1 &&
             OrderType() == OP_SELLLIMIT &&
             OrderOpenPrice() == 200000.0;

         if(A || B)
         {
            orderExists = true;
            break;
         }
      }
   }

   if(orderExists)
   {
      if(s_canToggle && g_autoTradingEnabled)
      {
         ToggleAutoTrading(false);
         s_canToggle = false;
      }

      // 指値注文を削除
      bool orderDeleted;
      do
      {
         orderDeleted = false;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
               if(OrderMagicNumber() != 0 &&
                  (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT))
               {
                  if(OrderDelete(OrderTicket()))
                  {
                     orderDeleted = true;
                  }
               }
            }
         }
      }
      while(orderDeleted);
   }
   else
   {
      if(!s_canToggle)
      {
         ToggleAutoTrading(s_lastManualState);
         s_canToggle = true;
      }
   }
}
