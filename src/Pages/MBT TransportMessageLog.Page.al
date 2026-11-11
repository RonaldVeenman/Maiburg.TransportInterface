page 52103 "MBT Transport Log"
{
    Caption = 'Transport Log';
    PageType = List;
    SourceTable = "MBT Transport Log";
    UsageCategory = History;
    ApplicationArea = All;
    Editable = false;
    DeleteAllowed = false;
    InsertAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ToolTip = 'Geeft het volgnummer van de logregel weer.';
                }
                field("Date/Time"; Rec."Date/Time")
                {
                    ToolTip = 'Geeft aan wanneer deze logregel is vastgelegd.';
                }
                field("Connector Code"; Rec."Connector Code")
                {
                    ToolTip = 'Geeft de betrokken transporteur-connector weer.';
                }
                field("Whse. Shipment No."; Rec."Whse. Shipment No.")
                {
                    ToolTip = 'Geeft het nummer van de betrokken magazijnverzending weer.';
                }
                field(Direction; Rec.Direction)
                {
                    ToolTip = 'Geeft aan of het bericht uitgaand of inkomend was.';
                }
                field(Status; Rec.Status)
                {
                    ToolTip = 'Geeft het resultaat van de communicatie weer.';
                }
                field("Message Text"; Rec."Message Text")
                {
                    ToolTip = 'Geeft het bericht of de foutmelding weer.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ShowRequestPayload)
            {
                Caption = 'Verzoek tonen';
                Image = ViewDetails;
                ApplicationArea = All;
                ToolTip = 'Toont de inhoud van het verzonden bericht (request payload).';

                trigger OnAction()
                var
                    InStream: InStream;
                    PayloadText: Text;
                begin
                    Rec.CalcFields("Request Payload");
                    if not Rec."Request Payload".HasValue() then
                        exit;
                    Rec."Request Payload".CreateInStream(InStream, TextEncoding::UTF8);
                    InStream.ReadText(PayloadText);
                    Message(PayloadText);
                end;
            }
            action(ShowResponsePayload)
            {
                Caption = 'Antwoord tonen';
                Image = ViewDetails;
                ApplicationArea = All;
                ToolTip = 'Toont de inhoud van het ontvangen bericht (response payload).';

                trigger OnAction()
                var
                    InStream: InStream;
                    PayloadText: Text;
                begin
                    Rec.CalcFields("Response Payload");
                    if not Rec."Response Payload".HasValue() then
                        exit;
                    Rec."Response Payload".CreateInStream(InStream, TextEncoding::UTF8);
                    InStream.ReadText(PayloadText);
                    Message(PayloadText);
                end;
            }
        }
    }
}
