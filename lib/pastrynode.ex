defmodule PastryNode do
    use GenServer
    def start_link(x,_,numRequests) do
    input_srt = Integer.to_string(x)
    nodeid = Base.encode16(:crypto.hash(:md5, input_srt))
    GenServer.start_link(__MODULE__, {nodeid,numRequests}, name: String.to_atom("n#{nodeid}"))    
    end

    def init({selfid,numRequests}) do        
        routetable = Matrix.from_list([[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[]])
        {:ok, {selfid,[selfid],routetable,numRequests,0}}
    end

    def route_lookup(key, leaf, routetable , selfid ) do
        {keyval,_} = Integer.parse(key,16)
        {firstleaf,_} = Integer.parse(List.first(leaf),16)
        {lastleaf,_} = Integer.parse(List.last(leaf),16)

        #check leaf set
        if ((keyval >= firstleaf) &&(keyval <= lastleaf)) do
            route_to = Enum.min_by(leaf, fn(x) -> Kernel.abs(elem(Integer.parse(x,16),0) - keyval) end)
        else #check routing table
            [{match_type, common}|_] = String.myers_difference(selfid,key)
            if match_type == :eq do
                common_len = String.length common
            else
                common_len = 0
            end
                
            {next_digit,_} = Integer.parse(String.slice(key,common_len,1),16)
             if (routetable[common_len][next_digit] != nil) do
                route_to = routetable[common_len][next_digit] 
             else #check all other routing table enteries 
                rtl = Matrix.to_list(routetable)
                routelist = Enum.slice(rtl,common_len,31)
                routelist = List.flatten(routelist)
                routelist = routelist ++ leaf 
                if (!Enum.empty?(routelist))do
                    candidate = Enum.min_by(routelist, fn(x) -> Kernel.abs(elem(Integer.parse(x,16),0) - keyval) end)
                    #compare candidate with self
                    cand_diff = Kernel.abs(elem(Integer.parse(candidate,16),0) - keyval)
                    self_diff = Kernel.abs(elem(Integer.parse(selfid,16),0) - keyval)
                    if(cand_diff < self_diff )do
                        route_to = candidate
                    else
                        route_to = nil
                    end
                else    
                    route_to = nil
                end  
             end
        end

    route_to
    end

    def handle_cast({:intialize_table,hostid},{selfid,leaf,routetable,req,num_created})do
        selflist = Enum.map String.codepoints(selfid), fn(x) -> elem(Integer.parse(x,16),0) end
        
        rows = Enum.to_list 0..31
        res = for row <- rows do 
            Map.get(put_in(routetable[row][Enum.at(selflist,row)], selfid),row)  
            end
        routetable = Matrix.from_list(res)

            #last lines
        GenServer.cast(String.to_atom("n"<>hostid),{:join,selfid,0})
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end

    def handle_cast({:intialize_table_first},{selfid,leaf,routetable,req,num_created})do
        selflist = Enum.map String.codepoints(selfid), fn(x) -> elem(Integer.parse(x,16),0) end
        
                rows = Enum.to_list 0..31
                res = for row <- rows do 
                    Map.get(put_in(routetable[row][Enum.at(selflist,row)], selfid),row)  
                    end
                routetable = Matrix.from_list(res)

            #last lines
        GenServer.cast(:listner,{:stated_s,selfid})        
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end



    def handle_cast({:join, incoming_node ,path_count},{selfid,leaf,routetable,req,num_created}) do
        #IO.puts "JOin MSG Recieved"
        path_count=path_count+1
        GenServer.cast(String.to_atom("n"<>incoming_node),{:routing_table,routetable,selfid,path_count})
       
        #NEXT HOP for incoming node
        next_hop = route_lookup(incoming_node,leaf,routetable,selfid)
        if next_hop == selfid do
            next_hop = nil
        end
        
        if next_hop != nil do
            GenServer.cast(String.to_atom("n#{next_hop}"),{:join_route,incoming_node,path_count})            
        else
            #Process.sleep(500)
            GenServer.cast(String.to_atom("n"<>incoming_node),{:leaf_table,leaf,selfid,path_count})
    
        end
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end

    def handle_cast({:join_route,incoming_node,path_count},{selfid,leaf,routetable,req,num_created}) do
      
        path_count=path_count+1
        GenServer.cast(String.to_atom("n"<>incoming_node),{:routing_table,routetable,selfid,path_count})
        
        #NEXT HOP for incoming node
        next_hop = route_lookup(incoming_node,leaf,routetable,selfid)
        if next_hop == selfid do
            next_hop = nil
        end
        if next_hop != nil do
            GenServer.cast(String.to_atom("n#{next_hop}"),{:join_route,incoming_node,path_count})            
        else
            #Process.sleep(500)
            GenServer.cast(String.to_atom("n"<>incoming_node),{:leaf_table,leaf,selfid,path_count})
        end
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end

     def handle_cast({:routing_table,new_route_table,sender_nodeid,_},{selfid,leaf,routetable,req,num_created}) do
        #dsa
        [{match_type, common}|_] = String.myers_difference(selfid,sender_nodeid)
        if match_type == :eq do
            common_len = String.length common
        else
            common_len = 0
        end
        
        
        rows = Enum.to_list 0..31        

        res = Enum.map rows, fn(row) -> if (row<= common_len) do Map.merge(new_route_table[row],routetable[row]) else routetable[row] end end
        res_map = Matrix.from_list(res)    


    {:noreply,{selfid,leaf,res_map,req,num_created}}
    end


     def handle_cast({:leaf_table,new_leaf_set,_,_},{selfid,leaf,routetable,req,num_created}) do
            
        merge_leaf = Enum.dedup(Enum.sort(new_leaf_set ++ leaf))
        # merge_size = Enum.count(merge_leaf)
        centre = Enum.find_index(merge_leaf, fn(x) -> x == selfid end)

        {small_leaf, large_leaf} = Enum.split(List.delete(merge_leaf,selfid),centre)

        small_size =  Enum.count(small_leaf)
        large_size =  Enum.count(large_leaf)
        
        if(small_size > 16) do
            small_leaf = Enum.slice(small_leaf, small_size-16, 16) 
            
        end
        if(large_size > 16) do
            large_leaf = Enum.slice(large_leaf, 0, 16) 
        end

        leaf = small_leaf ++ [selfid] ++ large_leaf

        rt_list = List.flatten(Matrix.to_list(routetable))
        route_table_list = Enum.dedup(Enum.sort(rt_list))
        route_table_list = List.delete(route_table_list,selfid)
        
        leaf_list = List.delete(leaf,selfid)
        #Create variable combined list
        Enum.map(route_table_list, fn(x) -> GenServer.call(String.to_atom("n"<>x),{:updatert,routetable,selfid}) end)
        
        Enum.map(leaf_list, fn(x) -> GenServer.call(String.to_atom("n"<>x),{:update_routeleaf_table,routetable,leaf,selfid}) end)

        #ADD RETURN list check here
        GenServer.cast(:listner,{:stated_s,selfid})
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end
    
    def handle_call({:updatert,incoming_routetable,sender_nodeid},_,{selfid,leaf,routetable,req,num_created}) do
        
        [{match_type, common}|_] = String.myers_difference(selfid,sender_nodeid)
        if match_type == :eq do
            common_len = String.length common
        else
            common_len = 0
        end
        rows = Enum.to_list 0..31        

        res = Enum.map rows, fn(row) -> if (row<= common_len) do Map.merge(incoming_routetable[row],routetable[row]) else routetable[row] end end
        res_map = Matrix.from_list(res)  


        {:reply,"ok",{selfid,leaf,res_map,req,num_created}} 
    end

    def handle_call({:update_routeleaf_table,incoming_routetable,new_leaf_set,sender_nodeid},_,{selfid,leaf,routetable,req,num_created}) do
       
        [{match_type, common}|_] = String.myers_difference(selfid,sender_nodeid)
        if match_type == :eq do
            common_len = String.length common
        else
            common_len = 0
        end
        rows = Enum.to_list 0..31        

        res = Enum.map rows, fn(row) -> if (row<= common_len) do Map.merge(incoming_routetable[row],routetable[row]) else routetable[row] end end
        res_map = Matrix.from_list(res)  
        
        merge_leaf = Enum.dedup(Enum.sort(new_leaf_set ++ leaf))
        # merge_size = Enum.count(merge_leaf)
        centre = Enum.find_index(merge_leaf, fn(x) -> x == selfid end)
        {small_leaf, large_leaf} = Enum.split(List.delete(merge_leaf,selfid),centre)
       
        small_size =  Enum.count(small_leaf)
        large_size =  Enum.count(large_leaf)
        
        if(small_size > 16) do
            small_leaf = Enum.slice(small_leaf, small_size-16,16) 
            
        end
        if(large_size > 16) do
            large_leaf = Enum.slice(large_leaf, 0,16) 
        end

        leaf = small_leaf ++ [selfid] ++ large_leaf


        {:reply,"ok",{selfid,leaf,res_map,req,num_created}} 
    end

    #ROUTING MSGS CODE


    def handle_cast({:create_n_requests},{selfid,leaf,routetable,req,num_created}) do
        if(num_created < req)do
            #key = String.slice(Base.encode16(:crypto.hash(:sha256, Integer.to_string(:rand.uniform(99999999)) )),32,32)
            key = Base.encode16(:crypto.hash(:md5, :crypto.strong_rand_bytes(50)))
            next_hop = route_lookup(key,leaf,routetable,selfid)
            if next_hop == selfid do
                next_hop = nil
            end
            if next_hop != nil do
                GenServer.cast(String.to_atom("n#{next_hop}"),{:route_message,key,"this is the msg",0})

            else
                GenServer.cast(:listner,{:delivery,0})

                #SEND hop COUNT 
            end    
            num_created = num_created+1
            Process.sleep(1000)
            GenServer.cast(String.to_atom("n"<>selfid),{:create_n_requests})
        end
    {:noreply,{selfid,leaf,routetable,req,num_created}}
    end

    def handle_cast({:route_message,key,msg,hop_count},{selfid,leaf,routetable,req,num_created}) do
        hop_count = hop_count + 1
        next_hop = route_lookup(key,leaf,routetable,selfid)
        if next_hop == selfid do
            next_hop = nil
        end
        if next_hop != nil do
            GenServer.cast(String.to_atom("n#{next_hop}"),{:route_message,key,msg,hop_count})
        
        else
            GenServer.cast(:listner,{:delivery,hop_count})
            #SEND hop COUNT 
        end
    {:noreply,{selfid,leaf,routetable,req,num_created}}   
    end
end