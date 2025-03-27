defmodule Xlsxir.ParseWorkbook do
  @moduledoc """
  Holds the SAX event instructions for parsing style data via `Xlsxir.SaxParser.parse/2`
  """

  @doc """
  sheets has multiple sheet map which consists of name, sheet_id and rid
  """
  defstruct sheets: [], tid: nil

  def sax_event_handler(:startDocument, _state) do
    %__MODULE__{tid: GenServer.call(Xlsxir.StateManager, :new_table)}
  end

  def sax_event_handler({:startElement, _, ~c"sheet", _, xml_attrs}, state) do
    sheet =
      Enum.reduce(xml_attrs, %{name: nil, sheet_id: nil, rid: nil}, fn attr, sheet ->
        case attr do
          {:attribute, ~c"name", _, _, name} ->
            %{sheet | name: name |> to_string}

          {:attribute, ~c"sheetId", _, _, sheet_id} ->
            {sheet_id, _} = sheet_id |> to_string |> Integer.parse()
            %{sheet | sheet_id: sheet_id}

          {:attribute, ~c"id", _, _, rid} ->
            "rId" <> rid = rid |> to_string
            {rid, _} = Integer.parse(rid)
            %{sheet | rid: rid}

          _ ->
            sheet
        end
      end)

    %__MODULE__{state | sheets: [sheet | state.sheets]}
  end

  def sax_event_handler(:endDocument, %__MODULE__{tid: tid} = state) do
    # The sheets are collected in reverse order (newest first), so we need to reverse them
    # to get the correct order as they appear in the workbook
    sorted_sheets = state.sheets
                   |> Enum.reverse()
                   |> Enum.sort_by(fn %{sheet_id: id} -> id end)
    
    # Store each sheet with its corresponding information
    sorted_sheets
    |> Enum.with_index(1)
    |> Enum.each(fn {%{sheet_id: sheet_id, name: name, rid: rid}, index} ->
      # Store by sheet position (1-based) for position-based lookups
      :ets.insert(tid, {index, name})
      
      # Store by sheet ID from the workbook for direct ID lookups
      :ets.insert(tid, {sheet_id, name})
      
      # Store the RID mapping with both sheet_id and name
      :ets.insert(tid, {:rid, rid, sheet_id, name})
      
      # Store filename to sheet name mapping (critical for correct sheet identification)
      sheet_filename = "sheet#{index}.xml"
      :ets.insert(tid, {:filename, sheet_filename, name})
      
      # Also store a positional mapping to connect worksheet position to sheet_id
      :ets.insert(tid, {:position, index, sheet_id})
    end)

    state
  end

  def sax_event_handler(_, state), do: state
end
