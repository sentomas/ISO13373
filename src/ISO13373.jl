using Dash
using DashBootstrapComponents
using PlotlyJS 
using CSV
using DataFrames
using FFTW
using Statistics
using DSP
using NativeFileDialog 
# this code with high fidelity and checked with 300K data points


# --- MANUAL FLAT TOP WINDOW (Crash-Proof) ---
# Standard coefficients for Flat Top window (ISO 18431-1)
function calc_flattop(n::Int)
    a0 = 0.21557895
    a1 = 0.41663158
    a2 = 0.277263158
    a3 = 0.083578947
    a4 = 0.006947368
    return [a0 - a1*cos(2π*k/(n-1)) + a2*cos(4π*k/(n-1)) - a3*cos(6π*k/(n-1)) + a4*cos(8π*k/(n-1)) for k in 0:n-1]
end

# --- APP SETUP ---
app = dash(external_stylesheets=[dbc_themes.SPACELAB])

app.layout = dbc_container(fluid=true, style=Dict("padding"=>"20px"), [
    
    # 1. HEADER
    dbc_row([
        dbc_col(html_h2("VIBRATION LAB", style=Dict("color"=>"#003366", "font-weight"=>"bold")), width=10),
        dbc_col(dbc_badge("v7.1 Stable", color="success", className="ms-1"), width=2)
    ], style=Dict("border-bottom"=>"2px solid #003366", "margin-bottom"=>"20px")),

    dbc_row([
        # --- 2. SIDEBAR ---
        dbc_col([
            dbc_card([
                dbc_cardheader("DATA SOURCE", style=Dict("font-weight"=>"bold")),
                dbc_cardbody([
                    html_label("Select File:"),
                    dbc_inputgroup([
                        dbc_input(id="input-path", type="text", placeholder="Click Browse...", style=Dict("flex"=>"1")),
                        dbc_button("📂 Browse", id="btn-browse", color="secondary") 
                    ], className="mb-3"),
                    dbc_button("Load Data", id="btn-load", color="primary", style=Dict("width"=>"100%", "font-weight"=>"bold")),
                    html_div(id="status-msg", style=Dict("color"=>"green", "margin-top"=>"10px", "font-weight"=>"bold"))
                ])
            ], style=Dict("margin-bottom"=>"20px")),

            dbc_card([
                dbc_cardheader("SETTINGS", style=Dict("font-weight"=>"bold")),
                dbc_cardbody([
                    html_label("Select Channel:"),
                    dcc_dropdown(id="drop-col", options=[], placeholder="Wait for load..."),
                    html_br(),
                    
                    html_label("Mode:"),
                    dcc_radioitems(id="radio-mode", 
                        options=[
                            Dict("label"=>"Waveform", "value"=>"time"), 
                            Dict("label"=>"FFT Spectrum", "value"=>"fft")
                        ], value="time", inline=true),
                    html_br(),
                    
                    html_label("Window Function:"),
                    dcc_dropdown(id="drop-win", 
                        options=[
                            Dict("label"=>"Hanning (General)", "value"=>"hann"),
                            Dict("label"=>"Hamming (Narrow Lobe)", "value"=>"hamm"),
                            Dict("label"=>"Flat Top (Amplitude Accurate)", "value"=>"flat"),
                            Dict("label"=>"Blackman (Low Leakage)", "value"=>"black"),
                            Dict("label"=>"Rectangular (None)", "value"=>"rect")
                        ], value="hann"),
                    html_br(),

                    html_label("Resolution:"),
                    dcc_dropdown(id="drop-res",
                        options=[
                            Dict("label"=>"Auto (Full)", "value"=>"auto"),
                            Dict("label"=>"32k Lines", "value"=>"32768"),
                            Dict("label"=>"16k Lines", "value"=>"16384"),
                            Dict("label"=>"8k Lines", "value"=>"8192"),
                            Dict("label"=>"4k Lines", "value"=>"4096")
                        ], value="auto")
                ])
            ])
        ], width=3), 

        # --- 3. GRAPH ---
        dbc_col([
            dbc_card([
                dbc_cardbody([
                    dcc_graph(id="main-plot", style=Dict("height"=>"75vh"))
                ])
            ], style=Dict("border"=>"1px solid #ddd"))
        ], width=9)
    ])
])

# --- STATE ---
global df_data = DataFrame()
global time_col_name = ""

# --- CALLBACKS ---
callback!(app, Output("input-path", "value"), Input("btn-browse", "n_clicks")) do n
    if n === nothing; return nothing; end
    path = pick_file() 
    return path == "" ? nothing : path
end

callback!(app, 
    Output("status-msg", "children"),
    Output("drop-col", "options"),
    Output("drop-col", "value"),
    Input("btn-load", "n_clicks"),
    State("input-path", "value")
) do n_clicks, path
    if n_clicks === nothing; return "Waiting...", [], nothing; end
    if path === nothing || path == ""; return "❌ Browse first.", [], nothing; end
    if !isfile(path); return "❌ File not found.", [], nothing; end

    try
        global df_data = CSV.read(path, DataFrame, types=Float32)
        cols = names(df_data)
        t_col = cols[1]
        if "Time [s]" in cols; t_col = "Time [s]"
        elseif any(occursin.("Time", cols)); t_col = cols[findfirst(occursin.("Time", cols))] end
        global time_col_name = t_col
        data_cols = filter(x -> x != t_col, cols)
        opts = [Dict("label"=>c, "value"=>c) for c in data_cols]
        return "✅ Loaded $(nrow(df_data)) pts (Full Fidelity).", opts, data_cols[1]
    catch e
        return "Error: $e", [], nothing
    end
end

callback!(app,
    Output("main-plot", "figure"),
    Input("drop-col", "value"),
    Input("radio-mode", "value"),
    Input("drop-res", "value"),
    Input("drop-win", "value")
) do col, mode, res, win
    if isempty(df_data) || col === nothing
        return PlotlyJS.Plot(scatter(x=[], y=[]), PlotlyJS.Layout(title="No Data Loaded"))
    end

    try
        raw_s = df_data[!, col]
        raw_t = df_data[!, time_col_name]
        
        trace = nothing
        layout = nothing

        if mode == "time"
            # Full Fidelity Time Trace (WebGL)
            trace = PlotlyJS.scattergl(
                x=raw_t, y=raw_s, mode="lines", name=col, 
                line=attr(color="#003366", width=1.0)
            )
            layout = PlotlyJS.Layout(
                title="Waveform: $col", 
                xaxis_title="Time [s]", yaxis_title="Amplitude", template="plotly_white"
            )
        else
            # FFT
            N_max = length(raw_s)
            N = (res == "auto") ? N_max : min(parse(Int, res) * 2, N_max)
            s = raw_s[1:N]
            
            # --- ROBUST WINDOW SELECTION ---
            w_vec = ones(N)
            if win == "hann"; w_vec = hanning(N)
            elseif win == "hamm"; w_vec = hamming(N)
            elseif win == "black"; w_vec = blackman(N)
            
            # Use our custom manual function for Flat Top
            elseif win == "flat"; w_vec = calc_flattop(N) 
            end
            
            # FFT Calc
            dt = mean(diff(raw_t[1:min(1000,end)]))
            fs = 1.0/dt
            
            # Standard Correction for Amplitude (Peak)
            correction = 2.0/sum(w_vec)
            if win == "rect"; correction = 1.0/N * 2.0; end
            
            mag = abs.(fft(s .* w_vec)) .* correction
            freqs = fftfreq(N, fs)
            
            half = div(N, 2)
            
            trace = PlotlyJS.scattergl(
                x=freqs[1:half], y=mag[1:half], mode="lines", name="Spectrum", 
                line=attr(color="#B22222", width=1)
            )
            layout = PlotlyJS.Layout(
                title="FFT: $col ($win window)", 
                xaxis_title="Freq [Hz]", yaxis_title="Peak Amp", template="plotly_white", 
                xaxis_range=[0, fs/2]
            )
        end
        
        return PlotlyJS.Plot(trace, layout)

    catch e
        return PlotlyJS.Plot(scatter(x=[],y=[]), PlotlyJS.Layout(title="Error: $e"))
    end
end

# --- RUN local ---
#println("Server running at http://127.0.0.1:8085")
#run_server(app, "127.0.0.1", 8085) 

#to run in render 
# Get the port from the environment, default to 8080 if not set
port = parse(Int, get(ENV, "PORT", "8080"))

println("Server running on 0.0.0.0:$port")
run_server(app, "0.0.0.0", port)