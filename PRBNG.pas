unit PRBNG;

interface

uses
  Classes, Windows, SysUtils, IdBaseComponent, IdComponent, IdRawBase, IdRawClient, IdIcmpClient;

const
  prDefaultCapacity: Byte = 14;
  prDefaultProbability: Extended = 0.5;
  prDefaultRangeMax: LongInt = 99;
  prDefaultRangeMin: LongInt = 0;

  prErrorDataLoad: String = 'Critical error! An error occurred while reading data from a resource!';
  prErrorIncorrectValue: String = 'Incorrect input value(s). Error returned!';
  prErrorInvalidValue: String = 'Invalid input value! The value has been set by default!';
  prErrorNotTrue: String = 'Failed to initialize the random number generator. The numbers are not truly random (they are pseudo-random).';
  prErrorPingFailed: String = 'Error! Attempting to ping failed!';

  pdLow: Integer = 0;
  pdHigh: Integer = 151199;
  pdLowByte: Byte = 0;
  pdHighByte: Byte = 99;
  pdLowSym: Byte = 1;
  pdHighSym: Byte = 240;

  prHostsNumber = 14;
  prHosts: array [0 .. prHostsNumber - 1] of String = ('google.com', 'yahoo.com', 'wordpress.com', 'ya.ru', 'bing.com', 'ask.com', 'mail.ru',
    'sohu.com', 'twitter.com', 'taobao.com', 'blogger.com', 'baidu.com', 'wikipedia.org', 'facebook.com');
  prPings = 20;
  prMaxPingIndex = prPings - 1;

type
  T100Bytes = array [0 .. 99] of Byte;
  TPDData = array [0 .. 151199] of T100Bytes;
  TDurations = array [0 .. 19] of Int64;
  PPDData = ^TPDData;

  TPBRNG = class(TComponent)
  private
    FCap: Byte;
    FDurations: TDurations;
    FInitShift: Int64;
    FMag: Int64;
    FMax: Int64;
    FMin: Int64;
    FPPD: PPDData;
    FProb: Extended;

    function BitStr10ToStr3(AStr10: String): String;
    function ConvIntoCentesimal(AValue: String): Extended;
    function CyclicShiftIndex(AIndex, AShift, AMax: Int64): Int64;
    function Decode240(A100Bytes: T100Bytes): String;
    function Encode240(AStr240: String): T100Bytes;
    function GetBit(var ABuf; AIndex: Integer): Boolean;
    function GetBitStr(ALWValue: LongWord; AN: Byte): String;
    function GetDRatio(AValue: Int64; ADurations: TDurations): Extended;
    function GetHost: String;
    function GetPingDuration(AHost: String; out PingDuration: Int64): Boolean;
    function GetRDigit(AIndex: Int64): Char;
    function GetRDigits(AIndex: Int64; ANum: Byte): String;
    procedure Init;
    procedure Load;
    function MakePing(AHost: String): Boolean;
    function MakePingSeries(AHost: String; out Durations: TDurations): Boolean;
    procedure NormalizeDurations(var Durations: TDurations);
    function ScaleTo(AValue: Extended; AMin, AMax: Int64): Int64;
    procedure SetBit(var ABuf; AIndex: Integer; Value: Boolean);
    function SetBits(AWord: Word; ABit: Byte; AState: Boolean = True): Word;
    function Str240Ok(AStr240: String): Boolean;
    function Str3Ok(AStr3: String): Boolean;
    function Str3ToBitStr10(AStr3: String): String;
    function PingRN(out RN: Extended): Boolean; overload;
    function PingRN(AMin, AMax: Int64; out RN: Int64): Boolean; overload;
    function PRandom(ADigits: Byte): Extended; overload;
    function PRandom(AMin, AMax: Int64): Int64; overload;
    procedure PRandomize;
    procedure Update;
    procedure UpdateMagnitude;

  public
    function GetRRandom(ACap: Byte): Extended; overload;
    function GetRandom(AMin, AMax: Int64): Int64; overload;
    function GetRandom(AMax: Int64): Int64; overload;
    function GetTrue(AProb: Extended): Boolean; overload;
    procedure SetRange(AMin, AMax: Int64); overload;
    procedure SetUp(AMin, AMax: Int64; ACap: Byte; AProb: Extended = 0.5); overload;
    procedure SetUp(AMin, AMax: Int64; ACap: Byte = 14); overload;
    procedure SetUp(AMin, AMax: Int64); overload;

  published
    constructor Create(AOwner: TComponent); override;

    function GetRandom: Int64; overload;
    function GetRRandom: Extended; overload;
    function GetTrue: Boolean; overload;
    procedure Randomize;
    procedure Reset;
    procedure SetCap(ACap: Byte = 14);
    procedure SetMax(AMax: Int64 = 99);
    procedure SetMin(AMin: Int64 = 0);
    procedure SetRange(AMax: Int64 = 99); overload;
    procedure SetProb(AProb: Extended = 0.5);
    procedure SetUp(AMax: Int64 = 99); overload;

    property Capacity: Byte read FCap write SetCap;
    property InitShift: Int64 read FInitShift;
    property Magnitude: Int64 read FMag;
    property Max: Int64 read FMax write SetMax;
    property Min: Int64 read FMin write SetMin;
    property Probability: Extended read FProb write SetProb;
  end;

procedure Register;

implementation
{$R PD.RES}
{$R TPBRNG.RES}

procedure Register;
begin
  RegisterComponents('MXUstin', [TPBRNG]);
end;

function TPBRNG.BitStr10ToStr3(AStr10: String): String;
{$I 'Standart.localvar'}
begin
  W := 0;
  for I := 1 to 10 do
    if AStr10[11 - I] = '1' then
      W := SetBits(W, I - 1, True)
    else
      W := SetBits(W, I - 1, False);
  Result := IntToStr(W);
  if Length(Result) = 1 then
    Result := '00' + Result;
  if Length(Result) = 2 then
    Result := '0' + Result;
end;

function TPBRNG.ConvIntoCentesimal(AValue: String): Extended;
{$I 'Standart.localvar'}
begin
  Ok := True;
  for I := Low(AValue) to High(AValue) do
    if not(AValue[I] in ['0' .. '9']) then
    begin
      Ok := False;
      Break;
    end;
  if Ok then
    Result := StrToFloat('0' + FormatSettings.DecimalSeparator + AValue)
  else
  begin
    Result := 0;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

constructor TPBRNG.Create(AOwner: TComponent);
begin
  inherited;
  Reset;
  Load;
  Randomize;
end;

function TPBRNG.CyclicShiftIndex(AIndex, AShift, AMax: Int64): Int64;
begin
  if ((AIndex >= 0) and (AIndex < (AMax))) and (AShift < AMax) and (AShift > 0) then
  begin
    if (AIndex >= AShift) then
      Result := AIndex - AShift
    else
      Result := AMax - (AShift - AIndex) + 1;
  end
  else
  begin
    Result := -1;
    Raise Exception.Create(prErrorIncorrectValue);
  end;
end;

function TPBRNG.Decode240(A100Bytes: T100Bytes): String;
{$I 'Standart.localvar'}
  ByteIndex, BitIndex: Integer;

begin
  Result := '';
  ByteIndex := 0;
  BitIndex := 7;
  repeat
    S := '0000000000';
    for I := 0 to 9 do
    begin
      S[I + 1] := GetBitStr(A100Bytes[ByteIndex], BitIndex)[1];
      if BitIndex > 0 then
        Dec(BitIndex)
      else
      begin
        Inc(ByteIndex);
        BitIndex := 7;
      end;
    end;
    Result := Result + BitStr10ToStr3(S);
  until ByteIndex = 100;
end;

function TPBRNG.Encode240(AStr240: String): T100Bytes;
{$I 'Standart.localvar'}
  Str240Index, BitIndex, ByteIndex: Integer;

begin
  for I := 0 to 99 do
    Result[I] := 0;
  Str240Index := 1;
  BitIndex := 7;
  ByteIndex := 0;
  repeat
    S := Str3ToBitStr10(Copy(AStr240, Str240Index, 3));
    for I := 1 to 10 do
    begin
      if S[I] = '0' then
        SetBit(Result, (ByteIndex * 8) + BitIndex, False)
      else
        SetBit(Result, (ByteIndex * 8) + BitIndex, True);
      if BitIndex > 0 then
        Dec(BitIndex)
      else
      begin
        Inc(ByteIndex);
        BitIndex := 7;
      end;
    end;
    Str240Index := Str240Index + 3;
  until Str240Index > 240;
end;

function TPBRNG.GetBit(var ABuf; AIndex: Integer): Boolean;
asm
  mov    ecx,    edx
  shr    edx,    3
  and    cl,     7
  mov    al,     [eax + edx]
  shr    al,     cl
  and    al,     1
end;

function TPBRNG.GetBitStr(ALWValue: LongWord; AN: Byte): String;
begin
  Result := IntToStr(ALWValue shr AN and 1);
end;

function TPBRNG.GetDRatio(AValue: Int64; ADurations: TDurations): Extended;
{$I 'Standart.localvar'}
begin
  LI := 0;
  for I := 0 to prMaxPingIndex do
    if ADurations[I] > LI then
      LI := ADurations[I];
  if AValue <= LI then
    Result := AValue / LI
  else
  begin
    Result := -1;
    Raise Exception.Create(prErrorIncorrectValue);
  end;
end;

function TPBRNG.GetHost: String;
{$I 'Standart.localvar'}
begin
  repeat
    Result := prHosts[System.Random(prHostsNumber)];
    Ok := MakePing(Result);
  until Ok;
end;

function TPBRNG.GetPingDuration(AHost: String; out PingDuration: Int64): Boolean;
{$I 'Standart.localvar'}
begin
  QueryPerformanceCounter(T1);
  if MakePing(AHost) then
    Result := True
  else
  begin
    Result := False;
    Raise Exception.Create(prErrorPingFailed);
  end;
  QueryPerformanceCounter(T2);
  PingDuration := T2 - T1;
end;

function TPBRNG.GetRandom: Int64;
begin
  Result := PRandom(FMin, FMax);
end;

function TPBRNG.GetRRandom: Extended;
begin
  Result := PRandom(FCap);
end;

function TPBRNG.GetTrue(AProb: Extended): Boolean;
{$I 'Standart.localvar'}
begin
  R := PRandom(FCap);
  if R > FProb then
    Result := False
  else
    Result := True;
end;

function TPBRNG.GetTrue: Boolean;
{$I 'Standart.localvar'}
begin
  R := PRandom(FCap);
  if R > FProb then
    Result := False
  else
    Result := True;
end;

function TPBRNG.GetRandom(AMin, AMax: Int64): Int64;
begin
  if AMax > AMin then
    Result := PRandom(AMin, AMax)
  else
    Raise Exception.Create(prErrorInvalidValue);
end;

function TPBRNG.GetRandom(AMax: Int64): Int64;
begin
  if AMax > 0 then
    Result := PRandom(0, AMax)
  else
    Raise Exception.Create(prErrorInvalidValue);
end;

function TPBRNG.GetRRandom(ACap: Byte): Extended;
begin
  Result := PRandom(ACap);
end;

function TPBRNG.GetRDigit(AIndex: Int64): Char;
begin
  if (AIndex >= 0) and (AIndex <= pdHigh) then
  begin
    System.Randomize;
    Result := Decode240(FPPD^[AIndex])[System.Random(pdHighSym) + pdLowSym];
  end
  else
  begin
    Result := '_';
    Raise Exception.Create(prErrorIncorrectValue);
  end;
end;

function TPBRNG.GetRDigits(AIndex: Int64; ANum: Byte): String;
{$I 'Standart.localvar'}
begin
  if (AIndex >= 0) and (AIndex <= pdHigh) then
  begin
    System.Randomize;
    Result := '';
    S := Decode240(FPPD^[AIndex]);
    for I := 0 to ANum - 1 do
      Result := Result + S[System.Random(pdHighSym) + pdLowSym]
  end
  else
  begin
    Result := '_';
    Raise Exception.Create(prErrorIncorrectValue);
  end;
end;

procedure TPBRNG.Init;
{$I 'Standart.localvar'}
begin
  FPPD := NIL;
  FInitShift := 0;
  for I := Low(FDurations) to High(FDurations) do
    FDurations[I] := 0;
end;

procedure TPBRNG.Load;
{$I 'Standart.localvar'}
begin
  FPPD := NIL;
  DHandle := FindResource(hInstance, 'DataArray', RT_RCDATA);
  if DHandle <> 0 then
  begin
    DHandle := LoadResource(hInstance, DHandle);
    if DHandle <> 0 then
      FPPD := LockResource(DHandle);
  end;
  if FPPD = nil then
    Raise Exception.Create(prErrorDataLoad);
end;

function TPBRNG.MakePing(AHost: String): Boolean;
begin
  Result := True;
  with TIdIcmpClient.Create(NIL) do
    try
      Host := AHost;
      ReceiveTimeout := 999;
      try
        Ping;
      except
        Result := False;
        Raise Exception.Create(prErrorPingFailed);
      end;
    finally
      Free;
    end;
end;

function TPBRNG.MakePingSeries(AHost: String; out Durations: TDurations): Boolean;
{$I 'Standart.localvar'}
begin
  for I := 0 to prMaxPingIndex do
    Durations[I] := 0;
  I := 0;
  repeat
    if GetPingDuration(AHost, LI) then
    begin
      E := False;
      for J := 0 to I do
        if Durations[J] = LI then
        begin
          E := True;
          Break;
        end;
      if not E then
      begin
        Durations[I] := LI;
        Inc(I);
      end;
    end
    else
    begin
      Result := False;
      Raise Exception.Create(prErrorPingFailed);
      Exit;
    end;
  until I = prMaxPingIndex + 1;
  Result := True;
end;

procedure TPBRNG.NormalizeDurations(var Durations: TDurations);
{$I 'Standart.localvar'}
begin
  LI := High(Int64);
  for I := 0 to prMaxPingIndex do
    if Durations[I] < LI then
      LI := Durations[I];
  for I := 0 to prMaxPingIndex do
    Durations[I] := Durations[I] - LI;
end;

function TPBRNG.PingRN(out RN: Extended): Boolean;
begin
  System.Randomize;
  if MakePingSeries(GetHost, FDurations) then
  begin
    NormalizeDurations(FDurations);
    RN := GetDRatio(FDurations[System.Random(prMaxPingIndex)], FDurations);
    Result := True;
  end
  else
  begin
    Result := False;
    Raise Exception.Create(prErrorPingFailed);
  end;
end;

function TPBRNG.PingRN(AMin, AMax: Int64; out RN: Int64): Boolean;
{$I 'Standart.localvar'}
begin
  if PingRN(R) then
  begin
    RN := ScaleTo(R, AMin, AMax);
    Result := True;
  end
  else
  begin
    Result := False;
    Raise Exception.Create(prErrorPingFailed);
  end;
end;

function TPBRNG.PRandom(ADigits: Byte): Extended;
{$I 'Standart.localvar'}
begin
  if (ADigits > 0) and (ADigits < 15) then
  begin
    System.Randomize;
    S := GetRDigits(CyclicShiftIndex(System.Random(pdHigh - 1), FInitShift, pdHigh), ADigits);
    Result := ConvIntoCentesimal(S);
  end
  else
  begin
    Result := -1;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

function TPBRNG.PRandom(AMin, AMax: Int64): Int64;
begin
  Result := ScaleTo(PRandom(FCap), AMin, AMax);
end;

procedure TPBRNG.PRandomize;
begin
  if not PingRN(1, pdHigh - 1, FInitShift) then
  begin
    System.Randomize;
    FInitShift := System.Random(pdHigh - 1);
    Raise Exception.Create(prErrorNotTrue);
  end;
end;

procedure TPBRNG.Randomize;
begin
  PRandomize;
end;

procedure TPBRNG.Reset;
begin
  SetUp(prDefaultRangeMax);
  Init;
end;

function TPBRNG.ScaleTo(AValue: Extended; AMin, AMax: Int64): Int64;
{$I 'Standart.localvar'}
begin
  LI := AMin - 1;
  LJ := AMax + 1;
  repeat
    Result := Round(AValue * (LJ - LI)) + LI;
  until (Result >= AMin) and (Result <= AMax);
end;

procedure TPBRNG.SetBit(var ABuf; AIndex: Integer; Value: Boolean);
asm
  test cl, cl
  jnz  @set_bit
  mov  ecx, edx
  shr  edx, 3
  and  ecx, 7
  btr  [eax+edx], ecx
  ret
@set_bit:
  mov  ecx, edx
  shr  edx, 3
  and  ecx, 7
  bts  [eax+edx], ecx
end;

function TPBRNG.SetBits(AWord: Word; ABit: Byte; AState: Boolean = True): Word;
begin
  if AState then
    Result := AWord or (1 shl ABit)
  else
    Result := AWord and (not(1 shl ABit));
end;

procedure TPBRNG.SetCap(ACap: Byte);
begin
  if (ACap > 0) and (ACap < 15) then
  begin
    FCap := ACap;
  end
  else
  begin
    FCap := prDefaultCapacity;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetMax(AMax: Int64);
begin
  if (AMax >= Low(Int64)) and (AMax <= High(Int64)) then
  begin
    FMax := AMax;
    UpdateMagnitude;
  end
  else
  begin
    FMax := prDefaultRangeMax;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetMin(AMin: Int64);
begin
  if (AMin >= Low(Int64)) and (AMin <= High(Int64) - prDefaultRangeMax) then
  begin
    FMin := AMin;
    UpdateMagnitude;
  end
  else
  begin
    FMin := prDefaultRangeMin;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetProb(AProb: Extended);
begin
  if (AProb >= 0) and (AProb <= 1) then
  begin
    FProb := AProb;
  end
  else
  begin
    FProb := prDefaultProbability;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetRange(AMin, AMax: Int64);
begin
  if (AMax > AMin) then
  begin
    SetMin(AMin);
    SetMax(AMax);
    UpdateMagnitude;
  end
  else
  begin
    FMin := prDefaultRangeMin;
    FMax := prDefaultRangeMax;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetRange(AMax: Int64);
begin
  if (AMax > 0) then
  begin
    SetMin;
    SetMax(AMax);
    UpdateMagnitude;
  end
  else
  begin
    FMin := prDefaultRangeMin;
    FMax := prDefaultRangeMax;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetUp(AMax: Int64);
begin
  SetUp(0, AMax, prDefaultCapacity, prDefaultProbability);
end;

function TPBRNG.Str240Ok(AStr240: String): Boolean;
{$I 'Standart.localvar'}
begin
  if Length(AStr240) = 240 then
  begin
    Ok := True;
    for I := 1 to 240 do
      if not(AStr240[I] in ['0' .. '9']) then
      begin
        Ok := False;
        Break;
      end;
    Result := Ok;
    if not Ok then
      Raise Exception.Create(prErrorInvalidValue);
  end
  else
  begin
    Result := False;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

function TPBRNG.Str3Ok(AStr3: String): Boolean;
begin
  if Length(AStr3) = 3 then
  begin
    try
      if StrToInt(AStr3) >= 0 then
        Result := True
      else
        Result := False;
    except
      Result := False;
      Raise Exception.Create(prErrorInvalidValue);
    end;
  end
  else
  begin
    Result := False;
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

function TPBRNG.Str3ToBitStr10(AStr3: String): String;
{$I 'Standart.localvar'}
begin
  if Str3Ok(AStr3) then
  begin
    W := StrToInt(AStr3);
    Result := '0000000000';
    for I := 0 to 9 do
      Result[10 - I] := GetBitStr(W, I)[1];
  end
  else
  begin
    Result := '';
    Raise Exception.Create(prErrorInvalidValue);
  end;
end;

procedure TPBRNG.SetUp(AMin, AMax: Int64; ACap: Byte; AProb: Extended);
begin
  SetRange(AMin, AMax);
  SetCap(ACap);
  SetProb(AProb);
end;

procedure TPBRNG.SetUp(AMin, AMax: Int64; ACap: Byte);
begin
  SetUp(AMin, AMax, ACap, prDefaultProbability);
end;

procedure TPBRNG.SetUp(AMin, AMax: Int64);
begin
  SetUp(AMax, AMin, prDefaultCapacity, prDefaultProbability);
end;

procedure TPBRNG.Update;
begin
  UpdateMagnitude;
end;

procedure TPBRNG.UpdateMagnitude;
begin
  FMag := ABS(FMax - FMin) + 1;
end;

end.
