//+------------------------------------------------------------------+
//|                                                  SumahoTeisi.mq5 |
//|                                         Copyright 2025, HosonoP |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HosonoP"
#property version   "1.00"
#property strict

#include "SumahoTeisi_Common.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| MT5用定義                                                         |
//+------------------------------------------------------------------+
#define MT_WMCMD_EXPERTS   32851

//+------------------------------------------------------------------+
//| DLLインポート                                                     |
//+------------------------------------------------------------------+
#import "user32.dll"
int GetAncestor(int hWnd, int flags);
int PostMessageW(int hWnd, int Msg, int wParam, int lParam);
#import

//+------------------------------------------------------------------+
//| グローバルオブジェクト                                            |
//+------------------------------------------------------------------+
CTrade trade;

//+------------------------------------------------------------------+
//| 自動売買の状態を切り替える（MT5版）                               |
//+------------------------------------------------------------------+
void AlgoTradingStatus(bool newStatus)
{
   bool currentStatus = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   if(currentStatus != newStatus)
   {
      int hwnd = (int)ChartGetInteger(0, CHART_WINDOW_HANDLE);
      int main = GetAncestor(hwnd, GA_ROOT);
      PostMessageW(main, WM_COMMAND, MT_WMCMD_EXPERTS, 0);

      g_autoTradingEnabled = newStatus;
      LogMessage("MetaTrader Auto Trading: " + (newStatus ? "ON" : "OFF"));

      if(InpShowPopupMessages)
      {
         Alert("MetaTrader自動売買が", (newStatus ? "有効" : "無効"), "になりました");
      }
   }
}

//+------------------------------------------------------------------+
//| 手動切り替え関数                                                  |
//+------------------------------------------------------------------+
void ManualToggle()
{
   if(s_canToggle && !g_eaStopped)
   {
      bool newState = !g_autoTradingEnabled;
      AlgoTradingStatus(newState);
      s_lastManualState = newState;
   }
}

//+------------------------------------------------------------------+
//| 全ポジション決済（MT5版）                                         |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(trade.PositionClose(ticket))
         {
            LogMessage("Position closed: Ticket=" + IntegerToString(ticket));
         }
         else
         {
            LogMessage("Failed to close position: Ticket=" + IntegerToString(ticket) +
                       " Error=" + IntegerToString(GetLastError()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 全オーダー削除（MT5版）                                           |
//+------------------------------------------------------------------+
void DeleteAllOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(trade.OrderDelete(ticket))
         {
            LogMessage("Order deleted: Ticket=" + IntegerToString(ticket));
         }
         else
         {
            LogMessage("Failed to delete order: Ticket=" + IntegerToString(ticket) +
                       " Error=" + IntegerToString(GetLastError()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 全ポジション・オーダー決済（MT5版）                               |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders()
{
   CloseAllPositions();
   DeleteAllOrders();
}

//+------------------------------------------------------------------+
//| 価格制限による処理                                                |
//+------------------------------------------------------------------+
void ProcessPriceLimitStop(int limitType)
{
   string reason = (limitType == 1) ? "価格超過" : "価格割れ";
   double limitPrice = (limitType == 1) ? InpUpperPriceLimit : InpLowerPriceLimit;
   double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);

   // 動作モードの説明
   string actionDesc = "";
   switch(InpPriceLimitAction)
   {
      case ACTION_CLOSE_ONLY:        actionDesc = "全決済"; break;
      case ACTION_CLOSE_AND_DELETE:  actionDesc = "全決済＋注文削除"; break;
      case ACTION_CLOSE_DELETE_STOP: actionDesc = "全決済＋注文削除＋自動売買停止"; break;
   }

   string subject = "【SumahoTeisi】" + reason;
   string message = "【警告】" + reason + "を検出！ Price=" + DoubleToString(currentPrice, Digits()) +
                    " Limit=" + DoubleToString(limitPrice, Digits()) + " 実行: " + actionDesc;

   // 全通知送信（アラート、スマホ、メール）
   SendAllNotifications(subject, message);

   // 全ポジション決済（全モードで実行）
   CloseAllPositions();
   LogMessage("全ポジション決済完了");

   // 待機注文削除（ACTION_CLOSE_AND_DELETE以上）
   if(InpPriceLimitAction >= ACTION_CLOSE_AND_DELETE)
   {
      DeleteAllOrders();
      LogMessage("待機注文削除完了");
   }

   // 自動売買をOFF（ACTION_CLOSE_DELETE_STOP）
   if(InpPriceLimitAction >= ACTION_CLOSE_DELETE_STOP)
   {
      AlgoTradingStatus(false);
      g_eaStopped = true;
      s_priceLimitTriggered = true;
      LogMessage("自動売買停止完了");
   }
}

//+------------------------------------------------------------------+
//| 初期化関数                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   LogMessage("EA initialized");
   LogMessage("Upper Price Limit: " + (InpUpperPriceLimit > 0 ? DoubleToString(InpUpperPriceLimit, Digits()) : "Disabled"));
   LogMessage("Lower Price Limit: " + (InpLowerPriceLimit > 0 ? DoubleToString(InpLowerPriceLimit, Digits()) : "Disabled"));

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
   double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
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
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         string symbol = OrderGetString(ORDER_SYMBOL);
         ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);

         A = (StringFind(symbol, "USDJPY") != -1 &&
              orderType == ORDER_TYPE_SELL_LIMIT &&
              openPrice == 200.0);
         B = (StringFind(symbol, "BTCUSD") != -1 &&
              orderType == ORDER_TYPE_SELL_LIMIT &&
              openPrice == 200000.0);

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
         AlgoTradingStatus(false);
         s_canToggle = false;
      }

      // 指値注文を削除
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            long magic = OrderGetInteger(ORDER_MAGIC);
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

            if(magic != 0 && (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT))
            {
               trade.OrderDelete(ticket);
            }
         }
      }
   }
   else
   {
      if(!s_canToggle)
      {
         AlgoTradingStatus(s_lastManualState);
         s_canToggle = true;
      }
   }
}
