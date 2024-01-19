local M = {}

local function clamp(controller, value)
    return math.min(math.max(value, controller.out_min), controller.out_max)
end

local function iterateController(controller, desired_value, actual_value, iteration_time)
    controller.error = desired_value - actual_value
    controller.integral = controller.integral_prior + controller.error * iteration_time
    controller.derivative = (controller.error - controller.error_prior) / iteration_time

    controller.error_prior = controller.error
    controller.integral_prior = controller.integral

    local output = controller.KP * controller.error + controller.integral_active * controller.KI * controller.integral +
        controller.KD * controller.derivative + controller.bias
    local clamped_output = clamp(controller, output)

    local is_output_clamped = math.abs(output - clamped_output) > 1E-10

    local sign = controller.error * controller.integral
    if is_output_clamped and sign > 0 then
        -- Saturation and integral making things worst
        controller.integral_active = 0
        if output > controller.out_max then
            return controller.out_max
        elseif output < controller.out_min then
            return controller.out_min
        end
    else
        -- No saturation
        controller.integral_active = 1
        return output
    end

end

local function iterate_v2(controller, desired_value, actual_value, iteration_time)
    --/*Compute all the working error variables*/
    local input = actual_value
    local error = desired_value - input
    controller.integral = controller.integral + (controller.KI * error)
    if controller.integral > controller.out_max then
        controller.integral = controller.out_max
    elseif controller.integral < controller.out_min then
        controller.integral = controller.out_min
    end
    local dInput = (input - controller.last_input);

    --/*Compute PID Output*/
    local output = (controller.KP * error) + controller.integral - (controller.KD * dInput);

    if output > controller.out_max then
        output = controller.out_max
    elseif output < controller.out_min then
        output = controller.out_min
    end
    controller.last_input = input
    return output --/ 1000
end

local function reset(controller)
    controller.integral = 0
    controller.last_input = 0
end

local function new(p, i, d, bias, out_min, out_max)
    local controller = {
        error_prior = 0,
        integral_prior = 0,
        KP = p,
        KI = i,
        KD = d,
        bias = bias,
        out_min = out_min,
        out_max = out_max,
        integral_active = 1,
        iterate = iterateController,
        clamp = clamp,


        integral = 0,
        last_input = 0,
        iterate_v2 = iterate_v2,
        reset = reset
    }
    return controller
end

M.new = new
return M
