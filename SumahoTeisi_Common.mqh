//+------------------------------------------------------------------+
//|                                          SumahoTeisi_Common.mqh  |
//|                                         Copyright 2025, HosonoP |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HosonoP"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| 入力パラメータ（共通）                                            |
//+------------------------------------------------------------------+
input double InpUpperPriceLimit = 0.0;    // 上限価格（0=無効）
input double InpLowerPriceLimit = 0.0;    // 下限価格（0=無効）
input bool   InpShowPopupMessages = true; // ポップアップメッセージ表示
input bool   InpPushNotification = false; // スマホ通知（プッシュ通知）
input bool   InpEmailNotification = false; // メール通知

//+------------------------------------------------------------------+
//| 静的変数（共通）                                                  |
//+------------------------------------------------------------------+
static bool s_canToggle = true;           // true: 停止できるモード
static bool s_lastManualState = true;     // 最後の手動設定状態
static bool s_priceLimitTriggered = false; // 価格制限でトリガーされたか

//+------------------------------------------------------------------+
//| グローバル変数（共通）                                            |
//+------------------------------------------------------------------+
bool g_autoTradingEnabled = true;
bool g_eaStopped = false;                 // EA停止フラグ

//+------------------------------------------------------------------+
//| 定数                                                              |
//+------------------------------------------------------------------+
#ifndef WM_COMMAND
#define WM_COMMAND 0x0111
#endif
#ifndef GA_ROOT
#define GA_ROOT    2
#endif

//+------------------------------------------------------------------+
//| 価格制限チェック（上限・下限）                                    |
//| 戻り値: 0=制限なし, 1=上限超え, -1=下限割れ                       |
//+------------------------------------------------------------------+
int CheckPriceLimit(double currentPrice)
{
   // 上限価格チェック（0より大きい場合のみ有効）
   if(InpUpperPriceLimit > 0.0 && currentPrice > InpUpperPriceLimit)
   {
      return 1; // 上限超え
   }

   // 下限価格チェック（0より大きい場合のみ有効）
   if(InpLowerPriceLimit > 0.0 && currentPrice < InpLowerPriceLimit)
   {
      return -1; // 下限割れ
   }

   return 0; // 制限なし
}

//+------------------------------------------------------------------+
//| 共通ログ出力                                                      |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
   Print("[SumahoTeisi] ", message);
}

//+------------------------------------------------------------------+
//| 共通アラート出力                                                  |
//+------------------------------------------------------------------+
void ShowAlert(string message)
{
   if(InpShowPopupMessages)
   {
      Alert(message);
   }
   LogMessage(message);
}

//+------------------------------------------------------------------+
//| スマホ通知（プッシュ通知）                                        |
//+------------------------------------------------------------------+
void SendPushNotify(string message)
{
   if(InpPushNotification)
   {
      if(!SendNotification(message))
      {
         LogMessage("Push notification failed. Error: " + IntegerToString(GetLastError()));
      }
      else
      {
         LogMessage("Push notification sent: " + message);
      }
   }
}

//+------------------------------------------------------------------+
//| メール通知                                                        |
//+------------------------------------------------------------------+
void SendEmailNotify(string subject, string message)
{
   if(InpEmailNotification)
   {
      if(!SendMail(subject, message))
      {
         LogMessage("Email notification failed. Error: " + IntegerToString(GetLastError()));
      }
      else
      {
         LogMessage("Email sent: " + subject);
      }
   }
}

//+------------------------------------------------------------------+
//| 全通知を送信（アラート、プッシュ、メール）                        |
//+------------------------------------------------------------------+
void SendAllNotifications(string subject, string message)
{
   ShowAlert(message);
   SendPushNotify(message);
   SendEmailNotify(subject, message);
}
