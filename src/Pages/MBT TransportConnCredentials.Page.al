page 52104 "MBT Transport Conn. Credent."
{
    Caption = 'Transport Connector Credentials';
    PageType = List;
    SourceTable = "MBT Transport Conn. Credent.";
    UsageCategory = Administration;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Connector Code"; Rec."Connector Code")
                {
                    ToolTip = 'Geeft de transporteur-connector weer waarbij dit geheim hoort.';
                }
                field("Secret Name"; Rec."Secret Name")
                {
                    ToolTip = 'Geeft de logische naam van het geheim weer, bijvoorbeeld ApiUserId, ApiKey of ContainerSasUrl.';
                }
                field(Description; Rec.Description)
                {
                    ToolTip = 'Geeft een omschrijving van het geheim weer.';
                }
                field("Has Value"; Rec."Has Value")
                {
                    ToolTip = 'Geeft aan of er al een waarde is vastgelegd in Isolated Storage.';
                }
                field("Key Vault Secret Name"; Rec."Key Vault Secret Name")
                {
                    ToolTip = 'Geeft de naam van het secret in Azure Key Vault weer (indien van toepassing).';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SetValue)
            {
                Caption = 'Waarde instellen';
                Image = EncryptionKeys;
                ApplicationArea = All;
                ToolTip = 'Opent een dialoogvenster om de geheime waarde in te voeren en veilig op te slaan in Isolated Storage.';

                trigger OnAction()
                var
                    IsolatedStorageEntry: Page "MBT Isolated Storage Entry";
                    NewValue: Text;
                begin
                    if Rec."Connector Code" = '' then
                        exit;
                    IsolatedStorageEntry.SetContext(Rec."Connector Code", Rec."Secret Name");
                    if IsolatedStorageEntry.RunModal() = Action::OK then begin
                        NewValue := IsolatedStorageEntry.GetValue();
                        TransportCredMgt.SetSecret(Rec."Connector Code", Rec."Secret Name", NewValue);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(ClearValue)
            {
                Caption = 'Waarde wissen';
                Image = Delete;
                ApplicationArea = All;
                ToolTip = 'Verwijdert de opgeslagen geheime waarde uit Isolated Storage.';

                trigger OnAction()
                begin
                    if Rec."Connector Code" = '' then
                        exit;
                    if not Confirm(ClearValueQst, false, Rec."Secret Name") then
                        exit;
                    TransportCredMgt.DeleteSecret(Rec."Connector Code", Rec."Secret Name");
                    CurrPage.Update(false);
                end;
            }
        }
    }

    var
        TransportCredMgt: Codeunit "MBT Transport Cred. Mgt.";
        ClearValueQst: Label 'Weet u zeker dat u de opgeslagen waarde voor %1 wilt verwijderen?';
}
