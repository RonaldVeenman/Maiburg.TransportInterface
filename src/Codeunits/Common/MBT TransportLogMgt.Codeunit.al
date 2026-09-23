codeunit 52101 "MBT Transport Log Mgt."
{
    /// <summary>Legt een regel vast in MBT Transport Log (FO §7.10).</summary>
    procedure LogEntry(ConnectorCode: Code[20]; WhseShptNo: Code[20]; Direction: Enum "MBT Transport Log Direction"; Status: Enum "MBT Transport Log Status"; MessageText: Text[2048])
    begin
        LogEntry(ConnectorCode, WhseShptNo, Direction, Status, MessageText, '', '');
    end;

    /// <summary>Legt een regel vast in MBT Transport Log, inclusief request-/response-payload voor troubleshooting.</summary>
    procedure LogEntry(ConnectorCode: Code[20]; WhseShptNo: Code[20]; Direction: Enum "MBT Transport Log Direction"; Status: Enum "MBT Transport Log Status"; MessageText: Text[2048]; RequestPayload: Text; ResponsePayload: Text)
    var
        TransportLog: Record "MBT Transport Log";
        RequestOutStream: OutStream;
        ResponseOutStream: OutStream;
    begin
        TransportLog.Init();
        TransportLog."Date/Time" := CurrentDateTime();
        TransportLog."Connector Code" := ConnectorCode;
        TransportLog."Whse. Shipment No." := WhseShptNo;
        TransportLog.Direction := Direction;
        TransportLog.Status := Status;
        TransportLog."Message Text" := MessageText;

        if RequestPayload <> '' then begin
            TransportLog."Request Payload".CreateOutStream(RequestOutStream, TextEncoding::UTF8);
            RequestOutStream.WriteText(RequestPayload);
        end;
        if ResponsePayload <> '' then begin
            TransportLog."Response Payload".CreateOutStream(ResponseOutStream, TextEncoding::UTF8);
            ResponseOutStream.WriteText(ResponsePayload);
        end;

        TransportLog.Insert(true);
    end;
}
